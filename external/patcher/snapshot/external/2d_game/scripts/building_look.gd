class_name BuildingLook
## Colour themes for buildings (the Minoan tile sprites), drawn with
## shaders/npc_recolor.gdshader: the tile art's colour families become
## slots - red plaster and columns (reds), wood and terracotta (oranges),
## gold trim and ochre (yellows), frescoes, tech and glass (blues), limestone
## and cream walls (pale) - then whole-building adjustments and, per part of
## the building (walls, floors, roofs, columns and decor), its own hue,
## brightness, saturation and tint.
## Same interface as the other generators (TEMPLATES = themes, generate,
## describe, PROPERTIES, apply) so the Library's property panel edits it.
## skin(look) makes the materials; dress(...) puts them on a building.

const SHADER := preload("res://shaders/npc_recolor.gdshader")
const CATEGORIES := [["walls", "Walls"], ["floors", "Floors"], ["roofs", "Roofs"], ["decor", "Columns and decor"]]

const BASE := {
	"plaster_color": Color(0.8, 0.15, 0.1), "plaster_amount": 0.0,
	"wood_color": Color(0.75, 0.42, 0.18), "wood_amount": 0.0,
	"gold_color": Color(0.95, 0.75, 0.3), "gold_amount": 0.0,
	"fresco_color": Color(0.2, 0.55, 1.0), "fresco_amount": 0.0,
	"stone_color": Color(0.95, 0.92, 0.85), "stone_amount": 0.0,
	"hue_shift": 0.0, "saturation": 1.0, "brightness": 1.0, "contrast": 1.0,
	"tint": Color(1, 1, 1), "tint_amount": 0.0, "slot_width": 1.0,
}
## The tile art's colour families (measured on the palace and warehouse
## sheets): [hue centre, half width, mean saturation, mean value].
const FAMILIES := {"fam_cloth": Vector4(0.0, 0.035, 0.84, 0.65), "fam_skin": Vector4(0.045, 0.02, 0.64, 0.62),
	"fam_pale": Vector4(0.092, 0.024, 0.48, 0.9), "fam_trim": Vector4(0.132, 0.022, 0.42, 0.9),
	"fam_tech": Vector4(0.575, 0.075, 0.62, 0.55)}
## The building slots -> the shader's (character-named) slots.
const SLOT_MAP := {"plaster": "cloth", "wood": "skin", "gold": "trim", "fresco": "tech", "stone": "pale"}

const TEMPLATES := {
	"minoan": {"name": "Minoan (as painted)"},
	"marble": {"name": "White marble", "stone_color": Color(0.97, 0.97, 0.98), "stone_amount": 1.0,
		"plaster_color": Color(0.85, 0.85, 0.88), "plaster_amount": 0.6, "gold_color": Color(0.9, 0.8, 0.45), "gold_amount": 0.5},
	"athenian": {"name": "Athenian blue", "plaster_color": Color(0.18, 0.32, 0.72), "plaster_amount": 1.0,
		"stone_color": Color(0.96, 0.96, 0.98), "stone_amount": 0.7},
	"spartan": {"name": "Spartan bronze", "plaster_color": Color(0.55, 0.08, 0.06), "plaster_amount": 1.0,
		"gold_color": Color(0.72, 0.45, 0.2), "gold_amount": 1.0, "stone_color": Color(0.78, 0.7, 0.6), "stone_amount": 0.6, "contrast": 1.1},
	"mycenaean": {"name": "Mycenaean stone and gold", "stone_color": Color(0.62, 0.6, 0.55), "stone_amount": 1.0,
		"plaster_color": Color(0.5, 0.2, 0.12), "plaster_amount": 0.8, "gold_color": Color(1.0, 0.8, 0.25), "gold_amount": 1.0,
		"brightness": 0.92},
	"ionian": {"name": "Ionian lapis and gold", "plaster_color": Color(0.16, 0.24, 0.62), "plaster_amount": 1.0,
		"gold_color": Color(0.98, 0.8, 0.35), "gold_amount": 1.0, "stone_color": Color(0.95, 0.93, 0.88), "stone_amount": 0.7,
		"fresco_color": Color(0.25, 0.4, 0.95), "fresco_amount": 1.0},
	"cycladic": {"name": "Cycladic whitewash", "stone_color": Color(0.99, 0.99, 0.98), "stone_amount": 1.0,
		"plaster_color": Color(0.12, 0.42, 0.78), "plaster_amount": 1.0, "fresco_color": Color(0.1, 0.5, 0.85), "fresco_amount": 1.0,
		"brightness": 1.06},
	"sandstone": {"name": "Desert sandstone", "stone_color": Color(0.9, 0.72, 0.48), "stone_amount": 1.0,
		"plaster_color": Color(0.75, 0.4, 0.2), "plaster_amount": 0.8, "fresco_color": Color(0.2, 0.6, 0.6), "fresco_amount": 0.8},
	"ice": {"name": "Ice palace", "stone_color": Color(0.85, 0.93, 1.0), "stone_amount": 1.0,
		"plaster_color": Color(0.45, 0.65, 0.9), "plaster_amount": 1.0, "gold_color": Color(0.85, 0.92, 1.0), "gold_amount": 0.9,
		"fresco_color": Color(0.6, 0.95, 1.0), "fresco_amount": 1.0},
	"obsidian": {"name": "Obsidian fortress", "stone_color": Color(0.32, 0.3, 0.36), "stone_amount": 1.0,
		"plaster_color": Color(0.35, 0.05, 0.08), "plaster_amount": 1.0, "fresco_color": Color(1.0, 0.25, 0.15), "fresco_amount": 1.0,
		"brightness": 0.85, "contrast": 1.2},
	"jade": {"name": "Jade temple", "plaster_color": Color(0.15, 0.55, 0.4), "plaster_amount": 1.0,
		"gold_color": Color(0.95, 0.82, 0.4), "gold_amount": 0.8, "stone_color": Color(0.88, 0.95, 0.88), "stone_amount": 0.6},
	"ruined": {"name": "Weathered ruin", "saturation": 0.45, "brightness": 0.85, "tint": Color(0.85, 0.8, 0.7), "tint_amount": 0.3},
	"night": {"name": "Night lights", "brightness": 0.7, "tint": Color(0.6, 0.65, 1.0), "tint_amount": 0.35,
		"fresco_color": Color(0.4, 1.0, 1.0), "fresco_amount": 1.0},
}

static var PROPERTIES: Array = [
	["#", "Red plaster and columns (the reds)"],
	["plaster_color", "Plaster colour", "color", 0, 0, "New colour for the red plaster bands, red columns and red fresco grounds.", []],
	["plaster_amount", "Plaster recolour", "float", 0.0, 1.0, "How much of the new plaster colour (0: as painted).", []],
	["#", "Wood and terracotta (the oranges)"],
	["wood_color", "Wood colour", "color", 0, 0, "New colour for wooden beams, doors, pots and terracotta.", []],
	["wood_amount", "Wood recolour", "float", 0.0, 1.0, "How much of the new wood colour.", []],
	["#", "Gold trim (the yellows)"],
	["gold_color", "Trim colour", "color", 0, 0, "New colour for gold trim, ochre and ornaments.", []],
	["gold_amount", "Trim recolour", "float", 0.0, 1.0, "How much of the new trim colour.", []],
	["#", "Frescoes, tech and glass (the blues)"],
	["fresco_color", "Fresco colour", "color", 0, 0, "New colour for blue frescoes, tech panels and glowing glass.", []],
	["fresco_amount", "Fresco recolour", "float", 0.0, 1.0, "How much of the new fresco colour.", []],
	["#", "Stone (sandstone and limestone)"],
	["stone_color", "Stone colour", "color", 0, 0, "New colour for the sandstone / limestone walls and paving.", []],
	["stone_amount", "Stone recolour", "float", 0.0, 1.0, "How much of the stone tint.", []],
	["#", "Whole building"],
	["hue_shift", "Hue shift", "float", -0.5, 0.5, "Turns every colour round the colour wheel.", []],
	["saturation", "Saturation", "float", 0.0, 2.0, "Greyer (0) to more vivid (2).", []],
	["brightness", "Brightness", "float", 0.3, 1.6, "Darker or lighter.", []],
	["contrast", "Contrast", "float", 0.5, 1.8, "Flatter or punchier shading.", []],
	["tint", "Tint", "color", 0, 0, "A colour cast over everything (weathering, night, magic).", []],
	["tint_amount", "Tint strength", "float", 0.0, 1.0, "How strong the tint is.", []],
	["slot_width", "Slot width", "float", 0.4, 2.0, "Widens or narrows which shades count as each colour family.", []],
] + _category_properties()


static func _category_properties() -> Array:
	var out := []
	for c in CATEGORIES:
		var k: String = c[0]
		out.append(["#", c[1]])
		out.append([k + "_hue", "Hue shift", "float", -0.5, 0.5, "Turns the %s' colours round the colour wheel." % c[1].to_lower(), []])
		out.append([k + "_bright", "Brightness", "float", 0.3, 1.8, "Darker or lighter: the %s only." % c[1].to_lower(), []])
		out.append([k + "_sat", "Saturation", "float", 0.0, 2.0, "Greyer or more vivid: the %s only." % c[1].to_lower(), []])
		out.append([k + "_tint", "Tint", "color", 0, 0, "A colour cast on the %s only." % c[1].to_lower(), []])
		out.append([k + "_tint_amount", "Tint strength", "float", 0.0, 1.0, "How strong that tint is.", []])
	return out
const STRUCTURAL := []


static func base_value(key: String) -> Variant:
	if BASE.has(key):
		return BASE[key]
	for c in CATEGORIES:
		if key.begins_with(c[0] + "_"):
			match key.substr(len(c[0]) + 1):
				"hue", "tint_amount": return 0.0
				"bright", "sat": return 1.0
				"tint": return Color.WHITE
	return null


static func generate(template: String, variant := 0) -> Dictionary:
	var p: Dictionary = BASE.duplicate()
	p.merge(TEMPLATES.get(template, TEMPLATES["minoan"]), true)
	p["template"] = template
	p["variant"] = variant
	if variant != 0:
		var g: float = fposmod(float(variant) * 0.618034, 1.0) - 0.5
		for k in ["plaster_color", "fresco_color"]:
			var c: Color = p[k]
			p[k] = Color.from_hsv(fposmod(c.h + g * 0.35, 1.0), c.s, c.v)
			p[k.replace("_color", "_amount")] = maxf(float(p[k.replace("_color", "_amount")]), 0.8)
	return p


static func describe(p: Dictionary) -> String:
	return "%s%s - a colour theme for the building tiles" % [p.get("name", "Look"),
		"" if int(p.get("variant", 0)) == 0 else " (variant %d)" % int(p["variant"])]


## The materials for a look: {category: ShaderMaterial}, kept on a Node
## (meta "look" and "materials") so live edits can update them.
static func skin(look: Dictionary) -> Node:
	var n := Node.new()
	n.name = "BuildingSkin"
	var mats := {}
	for c in CATEGORIES:
		var m := ShaderMaterial.new()
		m.shader = SHADER
		mats[c[0]] = m
	n.set_meta("look", look.duplicate())
	n.set_meta("materials", mats)
	_push(n)
	return n


static func _v(look: Dictionary, key: String) -> Variant:
	return look.get(key, base_value(key))


## Sets every material's parameters from the look.
static func _push(skin_node: Node) -> void:
	var look: Dictionary = skin_node.get_meta("look")
	var mats: Dictionary = skin_node.get_meta("materials")
	for c in CATEGORIES:
		var k: String = c[0]
		var m: ShaderMaterial = mats[k]
		for f in FAMILIES:
			m.set_shader_parameter(f, FAMILIES[f])
		for slot in SLOT_MAP:
			m.set_shader_parameter(SLOT_MAP[slot] + "_color", _v(look, slot + "_color"))
			m.set_shader_parameter(SLOT_MAP[slot] + "_amount", _v(look, slot + "_amount"))
		m.set_shader_parameter("hue_shift", float(_v(look, "hue_shift")) + float(_v(look, k + "_hue")))
		m.set_shader_parameter("saturation", float(_v(look, "saturation")) * float(_v(look, k + "_sat")))
		m.set_shader_parameter("brightness", float(_v(look, "brightness")) * float(_v(look, k + "_bright")))
		m.set_shader_parameter("contrast", _v(look, "contrast"))
		m.set_shader_parameter("slot_width", _v(look, "slot_width"))
		var own := float(_v(look, k + "_tint_amount")) > 0.0
		m.set_shader_parameter("tint", _v(look, k + "_tint") if own else _v(look, "tint"))
		m.set_shader_parameter("tint_amount", _v(look, k + "_tint_amount") if own else _v(look, "tint_amount"))


static func material(skin_node: Node, category: String) -> ShaderMaterial:
	return (skin_node.get_meta("materials") as Dictionary).get(category)


## Applies one property (live editing): `node` is the skin.
static func apply(node: Node, key: String, value: Variant) -> void:
	if node == null or not node.has_meta("look"):
		return
	var look: Dictionary = node.get_meta("look")
	look[key] = value
	node.set_meta("look", look)
	_push(node)


## Puts a skin's materials on CanvasItems (and their CanvasItem children).
static func dress(items: Array, skin_node: Node, category: String) -> void:
	var m := material(skin_node, category)
	for it in items:
		if it is CanvasItem and is_instance_valid(it):
			_dress_tree(it, m)


static func _dress_tree(n: CanvasItem, m: Material) -> void:
	if n is Sprite2D or n is TileMapLayer or n is Polygon2D or n is TextureRect:
		n.material = m
	for c in n.get_children():
		if c is CanvasItem:
			_dress_tree(c, m)
