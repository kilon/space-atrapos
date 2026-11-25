class_name StarGen
## Procedural stars (shaders/star.gdshader) from six templates, modelled on
## the reference suns in external/images/star_refs/:
##   yellow_sun  - fiery granulation, active regions, flares        (ref 1)
##   brown_dwarf - dark red turbulent bands with glowing seams       (ref 2)
##   white_star  - blue-white, mottled, a strong glow                (ref 3)
##   pulsar      - small blue star, field loops, sweeping twin beams (ref 4)
##   magnetar    - blue-violet, dense field loops, a violet beam     (ref 5)
##   red_giant   - red, stringy filaments, huge prominences          (ref 6)
## generate(template, variant, look) starts from the template with `look`
## (a star type's colours) applied, then - for variant > 0 - borrows features
## from the other templates and jitters colour, granulation and activity, so
## every system's sun is different.

const SHADER := preload("res://shaders/star.gdshader")
const NEUTRON := ["pulsar", "magnetar"]

const TEMPLATES := {
	"yellow_sun": {"name": "Yellow sun", "disc": 0.3,
		"c_dark": Color(0.5, 0.14, 0.01), "c_mid": Color(1.0, 0.52, 0.06), "c_hot": Color(1.0, 0.93, 0.6), "c_corona": Color(1.0, 0.68, 0.22),
		"gran_scale": 7.5, "contrast": 1.5, "filaments": 0.6, "active": 0.75, "spots": 0.15, "limb": 0.3,
		"corona": 0.9, "glow": 0.8, "prominences": 0.55, "prom_size": 0.8},
	"brown_dwarf": {"name": "Brown dwarf", "disc": 0.36,
		"c_dark": Color(0.08, 0.015, 0.015), "c_mid": Color(0.32, 0.07, 0.04), "c_hot": Color(1.0, 0.3, 0.08), "c_corona": Color(0.7, 0.14, 0.06),
		"gran_scale": 3.0, "contrast": 1.1, "filaments": 0.2, "active": 0.0, "spots": 0.0, "banded": 1.0, "band_count": 8.0, "limb": 0.55,
		"corona": 0.08, "glow": 0.3, "glow_size": 0.6, "prominences": 0.0, "spin": 0.03},
	"white_star": {"name": "White star", "disc": 0.3,
		"c_dark": Color(0.42, 0.52, 0.72), "c_mid": Color(0.72, 0.8, 0.94), "c_hot": Color(0.96, 0.98, 1.0), "c_corona": Color(0.7, 0.85, 1.0),
		"gran_scale": 5.0, "contrast": 1.4, "filaments": 0.25, "active": 0.4, "spots": 0.35, "limb": -0.15,
		"corona": 1.0, "glow": 1.25, "glow_size": 1.3, "prominences": 0.12, "prom_size": 0.5},
	"pulsar": {"name": "Pulsar", "disc": 0.13,
		"c_dark": Color(0.04, 0.18, 0.6), "c_mid": Color(0.2, 0.5, 1.0), "c_hot": Color(0.88, 0.96, 1.0), "c_corona": Color(0.3, 0.6, 1.0),
		"gran_scale": 6.0, "contrast": 1.3, "filaments": 0.7, "active": 0.5, "spots": 0.0, "limb": -0.2,
		"corona": 0.6, "glow": 1.0, "prominences": 0.0,
		"loops": 1.0, "loop_density": 1.0, "loop_extent": 4.5, "loop_color": Color(0.3, 0.6, 1.0), "loop_color2": Color(0.45, 0.75, 1.0),
		"axis": 0.65, "beam": 1.0, "beam_width": 0.16, "beam_wobble": 0.25, "beam_color": Color(0.75, 0.88, 1.0)},
	"magnetar": {"name": "Magnetar", "disc": 0.12,
		"c_dark": Color(0.08, 0.1, 0.55), "c_mid": Color(0.3, 0.45, 1.0), "c_hot": Color(0.9, 0.92, 1.0), "c_corona": Color(0.45, 0.45, 1.0),
		"gran_scale": 6.5, "contrast": 1.3, "filaments": 0.75, "active": 0.5, "spots": 0.0, "limb": -0.2,
		"corona": 0.6, "glow": 1.0, "prominences": 0.0,
		"loops": 1.0, "loop_density": 1.5, "loop_extent": 5.0, "loop_color": Color(0.25, 0.55, 1.0), "loop_color2": Color(0.62, 0.35, 1.0),
		"axis": 0.7, "beam": 1.0, "beam_width": 0.12, "beam_wobble": 0.0, "beam_color": Color(0.72, 0.5, 1.0)},
	"red_giant": {"name": "Red giant", "disc": 0.29,
		"c_dark": Color(0.3, 0.03, 0.02), "c_mid": Color(0.88, 0.2, 0.04), "c_hot": Color(1.0, 0.62, 0.22), "c_corona": Color(1.0, 0.3, 0.06),
		"gran_scale": 4.0, "contrast": 1.3, "filaments": 0.8, "active": 0.55, "spots": 0.1, "limb": 0.35,
		"corona": 0.7, "glow": 0.7, "prominences": 1.0, "prom_size": 1.25},
}

## The editable properties (the zoo's property panel builds itself from
## these): [key, label, type, min, max, help, (unused: [] = every star)].
const PROPERTIES := [
	["#", "Shape"],
	["seed", "Seed", "float", 0.0, 100.0, "Offsets every noise pattern: a different star with the same settings.", []],
	["disc", "Disc size", "float", 0.08, 0.42, "The disc's share of its frame: smaller leaves room for loops, beams and flares.", []],
	["detail", "Detail", "int", 2, 8, "Noise octaves: finer surface detail (costs more).", []],
	["spin", "Spin", "float", -0.1, 0.1, "Rotation speed of the surface (rad/s).", []],
	["tilt", "Tilt", "float", -1.6, 1.6, "Tilt of the rotation axis (rad).", []],
	["#", "Surface"],
	["c_dark", "Dark colour", "color", 0, 0, "Cool lanes, spots and the darkest granules.", []],
	["c_mid", "Main colour", "color", 0, 0, "The photosphere's main colour.", []],
	["c_hot", "Hot colour", "color", 0, 0, "The hottest granules, active regions and the core.", []],
	["gran_scale", "Granulation", "float", 1.0, 15.0, "Size of the boiling cells: higher = finer cells.", []],
	["contrast", "Contrast", "float", 0.3, 2.5, "Contrast between dark lanes and hot cells.", []],
	["filaments", "Filaments", "float", 0.0, 1.0, "Stringy bright and dark lanes across the surface.", []],
	["active", "Active regions", "float", 0.0, 1.5, "Bright, sparkling active regions.", []],
	["spots", "Spots", "float", 0.0, 1.0, "Dark starspots.", []],
	["banded", "Bands", "float", 0.0, 1.0, "Turbulent latitude bands (a brown dwarf's look).", []],
	["band_count", "Band count", "float", 2.0, 16.0, "How many bands.", []],
	["limb", "Limb", "float", -0.6, 0.9, "Limb darkening; negative makes the rim brighter (hot white stars).", []],
	["#", "Corona"],
	["c_corona", "Corona colour", "color", 0, 0, "Colour of the glow, corona and rays.", []],
	["corona", "Corona", "float", 0.0, 2.0, "Brightness of the corona and its rays.", []],
	["glow", "Glow", "float", 0.0, 2.5, "Brightness of the wide glow.", []],
	["glow_size", "Glow size", "float", 0.3, 2.5, "How far the glow reaches.", []],
	["prominences", "Prominences", "float", 0.0, 1.5, "Flaming filaments rising from the limb.", []],
	["prom_size", "Prominence size", "float", 0.3, 2.0, "How high the prominences reach.", []],
	["#", "Magnetic field and beams"],
	["loops", "Field loops", "float", 0.0, 1.5, "Brightness of the magnetic field lines (pulsars, magnetars).", []],
	["loop_density", "Loop density", "float", 0.3, 3.0, "How many field lines.", []],
	["loop_extent", "Loop reach", "float", 1.2, 7.0, "How far the field lines reach (in disc radii).", []],
	["loop_color", "Loop colour", "color", 0, 0, "Main colour of the field lines.", []],
	["loop_color2", "Loop colour 2", "color", 0, 0, "Second colour (the middle family of lines).", []],
	["axis", "Magnetic axis", "float", -3.15, 3.15, "Angle of the magnetic axis: the loops and beams follow it.", []],
	["beam", "Beams", "float", 0.0, 1.5, "Brightness of the twin beams.", []],
	["beam_width", "Beam width", "float", 0.03, 0.4, "Width of the beams.", []],
	["beam_wobble", "Precession", "float", 0.0, 1.0, "How far the beams sweep back and forth.", []],
	["beam_color", "Beam colour", "color", 0, 0, "Colour of the beams.", []],
]
## Properties that change the node's size: rebuilt rather than set.
const STRUCTURAL := ["disc"]


## Applies one property to a star node made by make() (live editing).
static func apply(node: Node, key: String, value: Variant) -> void:
	var mat: ShaderMaterial = node.material if node is CanvasItem else null
	if mat:
		mat.set_shader_parameter(key, value)


const MUTATIONS := ["flares", "sunspots", "active regions", "stormy bands", "calm surface", "coarse cells", "fine cells", "faint field loops"]
const NEUTRON_MUTATIONS := ["wide beams", "dense field", "precessing", "two-tone field", "quiet field"]
const META := ["name", "template", "variant", "tags", "color"]


static func generate(template: String, variant := 0, look := {}) -> Dictionary:
	var p: Dictionary = TEMPLATES.get(template, TEMPLATES["yellow_sun"]).duplicate()
	p.merge(look, true)
	p["template"] = template
	p["variant"] = variant
	p["seed"] = float(variant) * 5.17 + float(TEMPLATES.keys().find(template)) * 11.3
	var tags := []
	if variant != 0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["star", template, variant])
		var neutron: bool = template in NEUTRON
		var list: Array = NEUTRON_MUTATIONS if neutron else MUTATIONS
		var first := posmod(variant * 3, list.size())
		tags.append(list[first])
		while tags.size() < 2:
			var m = list[rng.randi() % list.size()]
			if not m in tags and not ((m == "fine cells" and "coarse cells" in tags) or (m == "coarse cells" and "fine cells" in tags)):
				tags.append(m)
		for m in tags:
			_mutate(p, m, rng)
		p["gran_scale"] = float(p.get("gran_scale", 5.0)) * rng.randf_range(0.8, 1.25)
		p["filaments"] = clampf(float(p.get("filaments", 0.3)) + rng.randf_range(-0.15, 0.15), 0.0, 1.0)
		p["tilt"] = rng.randf_range(-0.6, 0.6)
		p["spin"] = rng.randf_range(0.01, 0.04) * (1.0 if rng.randf() < 0.7 else -1.0)
		p["axis"] = rng.randf_range(-1.2, 1.2)
		# Colour: a small, distinct step in temperature tint per variant.
		var g: float = fposmod(float(variant) * 0.618034, 1.0) - 0.5
		var val := rng.randf_range(0.92, 1.08)
		for k in p:
			if p[k] is Color:
				var c: Color = p[k]
				var dh := g * (0.09 if neutron else 0.05)
				p[k] = Color.from_hsv(fposmod(c.h + dh, 1.0), clampf(c.s * rng.randf_range(0.9, 1.1), 0.0, 1.0), clampf(c.v * val, 0.0, 1.0))
	p["tags"] = tags
	p["color"] = (p["c_mid"] as Color).lerp(p["c_hot"], 0.4)
	return p


static func describe(p: Dictionary) -> String:
	var s: String = p.get("name", "Star")
	if not p.get("tags", []).is_empty():
		s += " · " + ", ".join(p["tags"])
	return s


static func _mutate(p: Dictionary, m: String, rng: RandomNumberGenerator) -> void:
	match m:
		"flares":
			p["prominences"] = rng.randf_range(0.7, 1.1)
			p["prom_size"] = rng.randf_range(0.9, 1.4)
		"sunspots":
			p["spots"] = rng.randf_range(0.5, 0.9)
		"active regions":
			p["active"] = rng.randf_range(0.8, 1.1)
		"stormy bands":
			p["banded"] = maxf(float(p.get("banded", 0.0)), rng.randf_range(0.35, 0.6))
			p["band_count"] = rng.randf_range(6.0, 11.0)
		"calm surface":
			p["filaments"] = 0.05
			p["active"] = float(p.get("active", 0.5)) * 0.4
			p["prominences"] = float(p.get("prominences", 0.5)) * 0.3
		"coarse cells":
			p["gran_scale"] = float(p.get("gran_scale", 5.0)) * 0.6
		"fine cells":
			p["gran_scale"] = float(p.get("gran_scale", 5.0)) * 1.6
		"faint field loops":
			p["loops"] = rng.randf_range(0.25, 0.45)
			p["loop_extent"] = rng.randf_range(1.6, 2.4)
			p["loop_color"] = p["c_hot"]
			p["loop_color2"] = p["c_corona"]
		"wide beams":
			p["beam_width"] = rng.randf_range(0.2, 0.3)
		"dense field":
			p["loop_density"] = rng.randf_range(1.6, 2.2)
		"precessing":
			p["beam_wobble"] = rng.randf_range(0.35, 0.6)
		"two-tone field":
			p["loop_color2"] = Color.from_hsv(rng.randf_range(0.72, 0.85), 0.7, 1.0)
		"quiet field":
			p["loops"] = rng.randf_range(0.45, 0.65)
			p["loop_extent"] = rng.randf_range(3.0, 3.8)


## A ColorRect showing the star, its disc `radius` px, centred on (0, 0).
static func make(p: Dictionary, radius: float) -> ColorRect:
	var rect := ColorRect.new()
	var disc: float = float(p.get("disc", 0.3))
	var size := radius / disc * 2.0
	rect.size = Vector2(size, size)
	rect.position = -rect.size / 2.0
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	for k in p:
		if not k in META:
			mat.set_shader_parameter(k, p[k])
	mat.set_shader_parameter("detail", 6 if radius > 200.0 else 5)
	rect.material = mat
	return rect
