extends VBoxContainer
## Field Computer tab: this planet's wildlife (SurfaceCreature.FAUNA for its
## terrain set) - each creature you've come near with its picture, what it
## is like and how many you've brought down; the rest as unknown shapes.
## (Seen and hunted: state["player"]["bestiary"], per species.)

var surface: Node

var _grid: GridContainer
var _summary: Label


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	_summary = UI.label("", 16, UI.TEXT_DIM)
	add_child(_summary)
	_grid = GridContainer.new()
	_grid.columns = 5   # (smaller cards, more to a row: the page never scrolls)
	_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 8)
	add_child(_grid)


const TEMPERS := {"grazer": "Grazer", "skittish": "Skittish - bolts from you", "slow": "Slow - hides when threatened",
	"bird": "Bird - flies off when you come near", "soar": "Flier - circles overhead", "drift": "Drifter - floats about",
	"predator": "PREDATOR - hunts you and others"}


func refresh() -> void:
	if surface == null:
		return
	UI.clear(_grid)
	var set_id := str(surface.pdata.get("tiles", ""))
	var table: Array = SurfaceCreature.FAUNA.get(set_id, [])
	var book: Dictionary = surface.state["player"].get("bestiary", {})
	var seen := 0
	var kills := 0
	for row in table:
		var sp: String = row[0]
		var e: Dictionary = book.get(sp, {})
		var known: bool = e.get("seen", false)
		seen += 1 if known else 0
		kills += int(e.get("kills", 0))
		_grid.add_child(_card(set_id, sp, known, int(e.get("kills", 0))))
	_summary.text = "%s wildlife: %d of %d kinds met  ·  %d hunted" % [surface.pdata["name"], seen, table.size(), kills] if not table.is_empty() \
		else "No wildlife has been recorded on %s." % surface.pdata["name"]


func _card(set_id: String, sp: String, known: bool, kills: int) -> Control:
	var spec: Dictionary = SurfaceCreature.SPECIES[sp]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(330, 74)
	row.size_flags_horizontal = SIZE_EXPAND_FILL   # (the cards share the row's width)
	var pic := TextureRect.new()
	pic.texture = ProcArt.get_tex("creature_%s_%s_stand" % [set_id, sp])
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(74, 70)
	if not known:
		pic.modulate = Color(0, 0, 0, 0.75)   # (a silhouette until you've met it)
	row.add_child(pic)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 2)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hostile: bool = spec["temper"] == "predator"
	text.add_child(UI.label(str(spec["name"]).capitalize() if known else "Unknown creature", 15,
		(Color(1.0, 0.55, 0.45) if hostile else Color.WHITE) if known else UI.TEXT_DIM))
	if known:
		var how: String = TEMPERS.get(spec["temper"], "")
		if spec.get("fights", false):
			how += " - fights back"
		text.add_child(UI.label(how, 12, UI.TEXT_DIM))
		text.add_child(UI.label("Health %d%s  ·  hunted %d" % [int(spec["hp"]), ("  ·  bite %d" % int(spec["bite"])) if spec.has("bite") else "", kills], 12,
			UI.GOLD if kills > 0 else UI.TEXT_DIM))
		row.tooltip_text = "%s\n%s\nHealth %d%s\nHunted: %d" % [str(spec["name"]).capitalize(), how, int(spec["hp"]),
			("  ·  bite %d" % int(spec["bite"])) if spec.has("bite") else "", kills]
	else:
		text.add_child(UI.label("Not met yet.", 12, UI.TEXT_DIM))
	for l in text.get_children():   # (the card keeps its width at any text size: the tooltip has it all)
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(text)
	return row
