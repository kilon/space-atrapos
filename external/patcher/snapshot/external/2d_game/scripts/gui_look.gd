class_name GuiLook
## Looks for the game's interface (NeonTheme): colours, panel opacity,
## corner cuts, border widths, glow, button fill, sheen, tooltips. Same
## interface as the other look generators (TEMPLATES, generate, describe,
## PROPERTIES, apply), so the Library's property panel edits the GUI - live,
## on every window, the panel itself included. Presets (Themes kind "gui")
## can follow empires, systems, conditions and story chapters.

const BASE := {"main_color": Color(1.0, 0.5, 0.1), "highlight_color": Color(1.0, 0.8, 0.45),
	"bg_color": Color(0.03, 0.018, 0.008), "bg_light": Color(0.085, 0.05, 0.02), "panel_alpha": 0.93,
	"text_color": Color(1.0, 0.89, 0.76), "text_dim": Color(0.78, 0.56, 0.36), "corner_cut": 1.0,
	"border_width": 1.0, "glow": 1.0, "button_fill": Color(0.05, 0.028, 0.01, 0.92), "sheen": 0.12,
	"tooltip_color": Color(1.0, 0.5, 0.1)}

static var TEMPLATES := _templates()


static func _templates() -> Dictionary:
	var t := {"neon": {"name": "Helm amber (default)"}}
	# The look before the amber console (teal glass, cyan borders, orange highlights).
	t["teal"] = {"name": "Teal console", "main_color": Color(0.24, 0.86, 1.0), "highlight_color": Color(1.0, 0.52, 0.12),
		"bg_color": Color(0.012, 0.045, 0.06), "bg_light": Color(0.03, 0.095, 0.115), "text_color": Color(0.86, 0.96, 1.0),
		"text_dim": Color(0.5, 0.7, 0.78), "button_fill": Color(0.02, 0.075, 0.095, 0.9), "sheen": 0.38,
		"tooltip_color": Color(0.24, 0.86, 1.0)}
	var names := {"minoa": "Minoan sea-green", "athens": "Athenian blue", "sparta": "Spartan red", "mycenae": "Mycenaean gold",
		"ionia": "Ionian violet", "pirates": "Sea Peoples blood"}
	for e in names:
		var p: Array = NeonTheme.PALETTES[e]
		t[e] = {"name": names[e], "main_color": p[0], "highlight_color": p[1], "bg_color": Color(p[2], 1.0), "bg_light": Color(p[3], 1.0),
			"tooltip_color": p[1]}
	t["amber"] = {"name": "Amber terminal", "main_color": Color(1.0, 0.68, 0.15), "highlight_color": Color(1.0, 0.9, 0.5),
		"bg_color": Color(0.05, 0.03, 0.0), "bg_light": Color(0.1, 0.06, 0.01), "text_color": Color(1.0, 0.82, 0.5),
		"text_dim": Color(0.75, 0.55, 0.3), "corner_cut": 0.0, "glow": 0.6, "button_fill": Color(0.1, 0.06, 0.0, 0.9), "tooltip_color": Color(1.0, 0.68, 0.15)}
	t["glass"] = {"name": "Ice glass", "main_color": Color(0.75, 0.9, 1.0), "highlight_color": Color(0.5, 0.8, 1.0),
		"bg_color": Color(0.08, 0.12, 0.18), "bg_light": Color(0.14, 0.2, 0.28), "panel_alpha": 0.75, "corner_cut": 2.0,
		"border_width": 0.7, "glow": 1.6, "sheen": 0.7, "tooltip_color": Color(0.75, 0.9, 1.0)}
	t["mono"] = {"name": "Monochrome", "main_color": Color(0.85, 0.85, 0.88), "highlight_color": Color(1, 1, 1),
		"bg_color": Color(0.04, 0.04, 0.05), "bg_light": Color(0.1, 0.1, 0.11), "text_color": Color(0.9, 0.9, 0.92),
		"text_dim": Color(0.55, 0.55, 0.6), "glow": 0.3, "button_fill": Color(0.08, 0.08, 0.09, 0.9), "tooltip_color": Color(1, 1, 1)}
	return t


const PROPERTIES := [
	["#", "Colours"],
	["main_color", "Main colour", "color", 0, 0, "The main colour: borders, lit buttons and tabs, headings, sliders.", []],
	["highlight_color", "Highlight", "color", 0, 0, "The second colour: hovered buttons, ticks, accents.", []],
	["text_color", "Text", "color", 0, 0, "The colour of ordinary text.", []],
	["text_dim", "Dim text", "color", 0, 0, "Hints, placeholders and separators.", []],
	["tooltip_color", "Tooltip border", "color", 0, 0, "The border of tooltips.", []],
	["#", "Panels"],
	["bg_color", "Panel background", "color", 0, 0, "The dark glass of panels and windows.", []],
	["bg_light", "Light background", "color", 0, 0, "Lighter areas: input fields, list rows, raised panels.", []],
	["panel_alpha", "Panel opacity", "float", 0.3, 1.0, "How see-through panels are (1: solid).", []],
	["button_fill", "Button fill", "color", 0, 0, "The inside of buttons.", []],
	["#", "Shape and glow"],
	["corner_cut", "Corner cut", "float", 0.0, 3.0, "Size of the cut corners (0: square corners).", []],
	["border_width", "Border width", "float", 0.3, 3.0, "Thickness of every border.", []],
	["glow", "Glow", "float", 0.0, 3.0, "Width of the neon glow around boxes.", []],
	["sheen", "Sheen", "float", 0.0, 1.0, "The light sheen along the top of buttons.", []],
]
const STRUCTURAL := []


static func base_value(key: String) -> Variant:
	return BASE.get(key)


static func generate(template: String, variant := 0) -> Dictionary:
	var p: Dictionary = BASE.duplicate()
	p.merge(TEMPLATES.get(template, TEMPLATES["neon"]), true)
	p["template"] = template
	p["variant"] = variant
	if variant != 0:
		var g: float = fposmod(float(variant) * 0.618034, 1.0)
		for k in ["main_color", "highlight_color", "tooltip_color"]:
			var c: Color = p[k]
			p[k] = Color.from_hsv(fposmod(c.h + g, 1.0), c.s, c.v)
	return p


static func describe(p: Dictionary) -> String:
	return "%s - the look of every window, button and tooltip (applies at once)" % p.get("name", "GUI")


## Applies a whole look to the interface.
static func apply_all(look: Dictionary) -> void:
	var l := {}
	for k in BASE:
		l[k] = look.get(k, BASE[k])
	NeonTheme.apply_look(l)


## One property (live editing): `node` keeps the look in meta "look".
static func apply(node: Node, key: String, value: Variant) -> void:
	if node == null:
		return
	var look: Dictionary = node.get_meta("look", {})
	look[key] = value
	node.set_meta("look", look)
	apply_all(look)
