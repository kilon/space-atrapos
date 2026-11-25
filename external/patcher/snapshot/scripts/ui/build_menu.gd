class_name BuildMenu
extends Control
## The builder's menu (N with the builder in hand - CosmosBuilds): the pieces
## by category, each with its picture and what it costs in the chosen tier;
## the tier (timber, stone, marble, bronze - how far each reaches out from a
## support, how tough), the empire's style, a paint, the mode (build,
## demolish, upgrade, paint) and snapping. A piece clicked: in hand, the menu
## shut.

const CAT_TABS := ["Foundations", "Floors", "Walls", "Openings", "Roofs", "Stairs", "Supports", "Fences", "Furniture"]

var builds: CosmosBuilds
var _cat := 0
var _tabs: HBoxContainer
var _grid: GridContainer
var _tiers: HBoxContainer
var _styles: HBoxContainer
var _paints: HBoxContainer
var _modes: HBoxContainer
var _snap: Button
var _note: Label
var _have: Label
var _root: VBoxContainer


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	Keybinds.register_menu(self)


func _build() -> void:
	_root = UI.modal(self, Color(NeonTheme.TEXT_DIM, 0.9), Vector2(1180, 0))
	var header := HBoxContainer.new()
	header.add_child(UI.label("BUILDER", 28, NeonTheme.HEAD))
	header.add_child(UI.spacer())
	header.add_child(EditorIcons.dress(UI.button("", close), "close", EditorIcons.tip("Close", "N / Esc", "Back to building.")))
	_root.add_child(header)
	_tabs = UI.tab_bar(CAT_TABS, _pick_cat, Color(), true, CAT_TABS.map(func(c): return "%s\nThe %s you can build: click one to take it in hand." % [c, str(c).to_lower()]))
	_root.add_child(_tabs)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_root.add_child(_grid)
	_tiers = _row("TIER")
	for i in BuildKit.TIERS.size():
		var tb := _toggle(BuildKit.tier_name(i), func(): _choose("tier", i))
		tb.tooltip_text = "%s\nBuilds in %s: spans %d cells out from a support, %d toughness. The pieces' costs are in it." % [BuildKit.tier_name(i),
			BuildKit.tier_name(i).to_lower(), BuildKit.span_of(i), int(BuildKit.TIERS[i]["hp"])]
		_tiers.add_child(tb)
	_styles = _row("STYLE")
	for s in BuildKit.STYLES:
		var sb := _toggle(BuildKit.STYLE_NAMES[s], func(): _choose("style", s))
		sb.tooltip_text = "%s\nThe pieces in the %s look." % [BuildKit.STYLE_NAMES[s], BuildKit.STYLE_NAMES[s]]
		_styles.add_child(sb)
	_paints = _row("PAINT")
	for i in BuildKit.PAINTS.size():
		var b := Swatch.new()
		b.paint = i
		b.tooltip_text = BuildKit.PAINT_NAMES[i]
		b.pressed.connect(func(): _choose("paint", i))
		_paints.add_child(b)
	_modes = _row("MODE")
	for m in CosmosBuilds.MODES:
		var mb := _toggle(CosmosBuilds.MODE_NAMES[m], func(): _choose("mode", m))
		mb.tooltip_text = CosmosBuilds.MODE_NAMES[m] + "\n" + str({"place": "Puts the piece in hand where you aim.", "remove": "Takes away the piece you aim at (some of its cost back).",
			"upgrade": "Remakes the piece you aim at in the tier picked above.", "paint": "Paints the piece you aim at in the paint picked above."}.get(m, ""))
		_modes.add_child(mb)
	_modes.add_child(UI.spacer())
	_snap = _toggle("Snapping", func(): _choose("snap", 0))
	_snap.tooltip_text = "Snapping\nOn: pieces fit to the grid and to the pieces next to them. Off: put them anywhere."
	_modes.add_child(_snap)
	_note = UI.label("", 16, NeonTheme.TEXT)
	_root.add_child(_note)
	_have = UI.label("", 16, NeonTheme.TEXT_DIM)
	_root.add_child(_have)


func _row(title: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := UI.label(title, 16, NeonTheme.HEAD)
	l.custom_minimum_size.x = 84
	h.add_child(l)
	_root.add_child(h)
	return h


func _toggle(text: String, act: Callable) -> Button:
	var b := UI.light_button(UI.button(text, act, 16))
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(118, 38)
	return b


func _choose(what: String, v) -> void:
	match what:
		"tier": CosmosBuilds.tier = int(v)
		"style": CosmosBuilds.style = str(v)
		"paint": CosmosBuilds.paint = int(v)
		"mode": CosmosBuilds.mode = str(v)
		"snap": CosmosBuilds.snap_on = not CosmosBuilds.snap_on
	refresh()


func _pick_cat(i: int) -> void:
	_cat = i
	refresh()


func open() -> void:
	if _root == null:
		_build()
	var cat := str(BuildKit.info(CosmosBuilds.piece).get("cat", "found"))
	for i in BuildKit.CATS.size():
		if BuildKit.CATS[i][0] == cat:
			_cat = i
	var was_open := visible and not HexReveal.closing(self)
	show()
	refresh()
	if not was_open:
		HexReveal.play(self)


func close() -> void:
	if not visible:
		return
	HexReveal.play(self, true, hide)


func refresh() -> void:
	UI.select_tab(_tabs, _cat)
	UI.clear(_grid)
	for id in BuildKit.ids_in(str(BuildKit.CATS[_cat][0])):
		var t := Tile.new()
		t.id = id
		t.cost = BuildKit.cost_text(BuildKit.cost(id, CosmosBuilds.tier))
		t.ok = _affordable(BuildKit.cost(id, CosmosBuilds.tier))
		t.picked = id == CosmosBuilds.piece
		t.tooltip_text = "%s\n%s" % [BuildKit.title(id, CosmosBuilds.tier), t.cost]
		t.pressed.connect(func():
			builds.choose(id)
			close())
		_grid.add_child(t)
	for i in _tiers.get_child_count() - 1:
		(_tiers.get_child(i + 1) as Button).set_pressed_no_signal(i == CosmosBuilds.tier)
	for i in BuildKit.STYLES.size():
		(_styles.get_child(i + 1) as Button).set_pressed_no_signal(BuildKit.STYLES[i] == CosmosBuilds.style)
	for i in BuildKit.PAINTS.size():
		var sw := _paints.get_child(i + 1) as Swatch
		sw.on = i == CosmosBuilds.paint
		sw.queue_redraw()
	for i in CosmosBuilds.MODES.size():
		(_modes.get_child(i + 1) as Button).set_pressed_no_signal(CosmosBuilds.MODES[i] == CosmosBuilds.mode)
	_snap.set_pressed_no_signal(CosmosBuilds.snap_on)
	_snap.text = "Snapping on" if CosmosBuilds.snap_on else "Snapping off"
	var T: Dictionary = BuildKit.TIERS[CosmosBuilds.tier]
	_note.text = "%s: floors reach %d cell%s past a wall or pillar  ·  %d toughness a wall  ·  %s style" % [T["name"], int(T["span"]) - 1, "" if int(T["span"]) == 2 else "s", BuildKit.hp_of("wall", CosmosBuilds.tier),
		BuildKit.STYLE_NAMES.get(CosmosBuilds.style, "")]
	var parts := []
	for k in ["timber", "stone", "marble", "bronze_ingots"]:
		parts.append("%d %s" % [CosmosBuilds.have(k), Items.display_name(k)])
	_have.text = "Free building: no costs, no supports needed" if BuildKit.free_build else "You have " + "  ·  ".join(parts)
	UI.scale_fonts(_root, "menu", 1.3)


static func _affordable(c: Dictionary) -> bool:
	if BuildKit.free_build:
		return true
	for k in c:
		if CosmosBuilds.have(k) < int(c[k]):
			return false
	return true


func _input(event: InputEvent) -> void:
	if not visible or UI.esc_menu_open():
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and Keybinds.pressed(event, "build_menu")):
		close()
		get_viewport().set_input_as_handled()


## A piece's tile: its picture, its name, what it costs (dim when you can't afford it).
class Tile:
	extends Button
	var id := ""
	var cost := ""
	var ok := true
	var picked := false

	func _init() -> void:
		custom_minimum_size = Vector2(212, 132)
		focus_mode = Control.FOCUS_NONE
		UI.light_button(self)
		toggle_mode = true

	func _ready() -> void:
		set_pressed_no_signal(picked)

	func _draw() -> void:
		var lit := button_pressed   # (the piece in hand: dark ink on the lit tile)
		var col := (NeonTheme.INK if lit else NeonTheme.HEAD) if ok else NeonTheme.DISABLED
		BuildKit.draw_icon(self, id, Rect2(Vector2(size.x * 0.5 - 38, 6), Vector2(76, 70)), col)
		var f := get_theme_default_font()
		var name := str(BuildKit.info(id).get("name", id))
		var fs := 16
		var w := f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(f, Vector2((size.x - w) * 0.5, 96), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, (NeonTheme.INK if lit else NeonTheme.TEXT) if ok else NeonTheme.DISABLED)
		var w2 := f.get_string_size(cost, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(f, Vector2((size.x - w2) * 0.5, 120), cost, HORIZONTAL_ALIGNMENT_LEFT, size.x - 8, 14, (NeonTheme.INK if lit else NeonTheme.TEXT_DIM) if ok else Color(1.0, 0.4, 0.3))


## A paint's swatch.
class Swatch:
	extends Button
	var paint := 0
	var on := false

	func _init() -> void:
		custom_minimum_size = Vector2(40, 38)
		focus_mode = Control.FOCUS_NONE
		UI.light_button(self)

	func _draw() -> void:
		var r := Rect2(Vector2(6, 6), size - Vector2(12, 12))
		if paint == 0:
			draw_line(r.position, r.end, NeonTheme.TEXT_DIM, 2.0)
			draw_rect(r, NeonTheme.TEXT_DIM, false, 1.5)
		else:
			draw_rect(r, BuildKit.PAINTS[paint])
		if on:
			draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), NeonTheme.HEAD, false, 2.5)
