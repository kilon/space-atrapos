class_name ShipParts
## The station Ship Designer's paint shop: a look recolours your ship's
## sprite (shaders/ship_paint.gdshader) - hue shift, saturation, brightness
## and a tint - keeping the art's shading and detail. Ready-made skins are
## bought once and stay owned (PlayerData.owned_parts); a custom paint job
## costs PAINT_JOB each time it changes.

const PAINT_JOB := 250

## Ready-made skins (tuned on the orange Atrapos fighter; they recolour any hull).
const SKINS := {
	"athenian_owl": {"name": "Athenian Owl", "hue": 0.55, "sat": 0.75, "bright": 1.1, "tint": Color(0.85, 0.9, 1.0), "tint_amt": 0.15, "price": 900},
	"spartan_bronze": {"name": "Spartan Bronze", "hue": -0.03, "sat": 0.7, "bright": 0.85, "tint": Color(0.8, 0.45, 0.2), "tint_amt": 0.25, "price": 900},
	"minoan_sea": {"name": "Minoan Sea", "hue": 0.42, "sat": 0.9, "bright": 1.0, "tint": Color(0.3, 0.9, 0.8), "tint_amt": 0.1, "price": 900},
	"mycenaean_gold": {"name": "Mycenaean Gold", "hue": 0.06, "sat": 0.85, "bright": 1.05, "tint": Color(1.0, 0.8, 0.3), "tint_amt": 0.2, "price": 900},
	"ionian_lapis": {"name": "Ionian Lapis", "hue": 0.6, "sat": 1.0, "bright": 0.9, "tint": Color(0.25, 0.35, 0.95), "tint_amt": 0.2, "price": 900},
	"sea_raider": {"name": "Sea Raider", "hue": -0.06, "sat": 0.35, "bright": 0.7, "tint": Color(0.8, 0.15, 0.1), "tint_amt": 0.2, "price": 700},
	"stealth": {"name": "Nyx Stealth", "hue": 0.0, "sat": 0.1, "bright": 0.5, "tint": Color(0.2, 0.2, 0.28), "tint_amt": 0.2, "price": 1200},
	"racer": {"name": "Olympic Racer", "hue": 0.0, "sat": 0.08, "bright": 1.35, "tint": Color(1, 1, 1), "tint_amt": 0.1, "price": 800},
	"olive": {"name": "Olive Grove Camo", "hue": 0.17, "sat": 0.5, "bright": 0.8, "tint": Color(0.45, 0.5, 0.3), "tint_amt": 0.25, "price": 700},
	"royal": {"name": "Royal Purple", "hue": 0.75, "sat": 0.9, "bright": 0.9, "tint": Color(0.55, 0.25, 0.75), "tint_amt": 0.15, "price": 1100},
}

const DEFAULT := {"hue": 0.0, "sat": 1.0, "bright": 1.0, "tint": "ffffffff", "tint_amt": 0.0}


## A complete paint look ({} / an older-format look = the factory paint).
static func normalized(look: Dictionary) -> Dictionary:
	var out := DEFAULT.duplicate()
	if not look.has("hue"):
		return out
	for k in DEFAULT:
		if look.has(k):
			out[k] = look[k]
	if look.has("skin"):
		out["skin"] = look["skin"]
	return out


static func is_factory(look: Dictionary) -> bool:
	var n := normalized(look)
	return is_equal_approx(float(n["hue"]), 0.0) and is_equal_approx(float(n["sat"]), 1.0) \
		and is_equal_approx(float(n["bright"]), 1.0) and float(n["tint_amt"]) <= 0.001


## The paint material for a look (null = factory paint).
static func material(look: Dictionary) -> ShaderMaterial:
	if is_factory(look):
		return null
	var n := normalized(look)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/ship_paint.gdshader")
	m.set_shader_parameter("hue", float(n["hue"]))
	m.set_shader_parameter("sat", float(n["sat"]))
	m.set_shader_parameter("bright", float(n["bright"]))
	m.set_shader_parameter("tint", Color(n["tint"]) if n["tint"] is String else n["tint"])
	m.set_shader_parameter("tint_amt", float(n["tint_amt"]))
	return m


## A skin as a look.
static func skin_look(id: String) -> Dictionary:
	var sk: Dictionary = SKINS[id]
	return {"hue": sk["hue"], "sat": sk["sat"], "bright": sk["bright"], "tint": (sk["tint"] as Color).to_html(), "tint_amt": sk["tint_amt"], "skin": id}


## Credits to change from one look to another (owned skins are free).
static func cost(old: Dictionary, new: Dictionary, owned: Array) -> int:
	var a := normalized(old)
	var b := normalized(new)
	if JSON.stringify(a) == JSON.stringify(b):
		return 0
	var sk: String = b.get("skin", "")
	if sk != "":
		return 0 if owned.has(sk) else int(SKINS[sk]["price"])
	return 0 if is_factory(b) else PAINT_JOB
