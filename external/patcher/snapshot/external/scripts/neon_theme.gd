class_name NeonTheme
extends RefCounted
## The game's GUI look, "Helm": a ship's console in amber on smoked black
## glass. Panels have two chamfered corners, a thin amber border with only a
## faint glow, bracket corners standing off the two square corners and a hatch
## of slanted ticks in the top-right corner (NeonBox); buttons have a lit rail
## down their left edge and light up solid amber (dark ink text) under the
## mouse; the selected tab is solid amber. Steel blue (INFO) is the second
## colour: data, friendly things, shields. Rajdhani headings and the chrome
## title font. build() makes a Theme that the Settings autoload puts on the
## root window, so every Control in every scene (menus, HUD, panels, popups,
## tooltips) follows it; the code-built panels use box() for the same style.
## (The variable names CYAN / PINK are older than the palette: CYAN is the
## main colour - amber - and PINK the highlight - pale gold.)

## One palette everywhere (it no longer follows the empire whose space you're
## in): CYAN = main neon colour, PINK = the highlight (now orange - the name is
## kept for the code using it), BG = panel background.
static var CYAN := Color(1.0, 0.5, 0.1)
static var PINK := Color(1.0, 0.8, 0.45)
static var VIOLET := Color(1.0, 0.65, 0.28)
static var BG := Color(0.03, 0.018, 0.008, 0.93)
static var BG_LIGHT := Color(0.085, 0.05, 0.02, 0.93)
## The second colour: data readouts, friendly things, shields, links.
static var INFO := Color(0.42, 0.7, 1.0)
## Headings and titles (a brighter amber).
static var HEAD := Color(1.0, 0.62, 0.22)
## Text on a lit (solid amber) box.
static var INK := Color(0.07, 0.035, 0.0)
static var empire := ""

## empire -> [main, highlight, background, light background]
const PALETTES := {
	"": [Color(1.0, 0.5, 0.1), Color(1.0, 0.8, 0.45), Color(0.03, 0.018, 0.008, 0.93), Color(0.085, 0.05, 0.02, 0.93)],
	"minoa": [Color(0.25, 0.92, 0.8), Color(1.0, 0.45, 0.35), Color(0.015, 0.05, 0.055, 0.92), Color(0.04, 0.11, 0.12, 0.92)],
	"athens": [Color(0.42, 0.72, 1.0), Color(1.0, 0.8, 0.32), Color(0.02, 0.035, 0.1, 0.92), Color(0.05, 0.08, 0.2, 0.92)],
	"sparta": [Color(1.0, 0.36, 0.3), Color(1.0, 0.72, 0.36), Color(0.07, 0.02, 0.02, 0.92), Color(0.15, 0.05, 0.05, 0.92)],
	"mycenae": [Color(1.0, 0.82, 0.38), Color(0.72, 0.9, 0.4), Color(0.06, 0.045, 0.02, 0.92), Color(0.13, 0.1, 0.05, 0.92)],
	"ionia": [Color(0.48, 0.6, 1.0), Color(1.0, 0.82, 0.42), Color(0.02, 0.025, 0.09, 0.92), Color(0.05, 0.06, 0.19, 0.92)],
	"pirates": [Color(1.0, 0.28, 0.18), Color(0.95, 0.86, 0.66), Color(0.05, 0.012, 0.012, 0.92), Color(0.12, 0.03, 0.03, 0.92)],
}


## The GUI used to re-theme itself for each empire's space; now it keeps one
## look everywhere, so this only makes sure the theme is built. (PALETTES
## stays for the GUI-look editor.) Returns true if it was (re)built.
static func set_empire(_e: String) -> bool:
	var e := ""
	if e == empire and _theme != null:
		return false
	empire = e
	var p: Array = PALETTES[e]
	CYAN = p[0]
	PINK = p[1]
	BG = p[2]
	BG_LIGHT = p[3]
	VIOLET = p[0].lerp(p[1], 0.5)
	if not custom.is_empty():
		_set_vars(custom)
	_rebuild()
	return true


## Applies a GUI look (GuiLook keys) to the whole interface, live. An empty
## look goes back to the plain palette.
static func apply_look(look: Dictionary) -> void:
	custom = look.duplicate()
	if look.is_empty():
		var p: Array = PALETTES[empire]
		CYAN = p[0]
		PINK = p[1]
		BG = p[2]
		BG_LIGHT = p[3]
		TEXT = Color(1.0, 0.89, 0.76)
		TEXT_DIM = Color(0.78, 0.56, 0.36)
		HEAD = Color(1.0, 0.62, 0.22)
		CUT_K = 1.0
		BORDER_K = 1.0
		GLOW_K = 1.0
		PANEL_ALPHA = 0.93
		BUTTON_FILL = Color(0.05, 0.028, 0.01, 0.92)
		SHEEN = 0.12
		TOOLTIP = Color(0, 0, 0, 0)
	else:
		_set_vars(look)
	VIOLET = CYAN.lerp(PINK, 0.5)
	if not look.is_empty():
		HEAD = l_head(look)
	_rebuild()


## A look's heading colour: its own, or its main colour brightened.
static func l_head(l: Dictionary) -> Color:
	return l.get("head_color", Color(l.get("main_color", CYAN)).lightened(0.15))


static func _set_vars(l: Dictionary) -> void:
	CYAN = l.get("main_color", CYAN)
	PINK = l.get("highlight_color", PINK)
	PANEL_ALPHA = float(l.get("panel_alpha", PANEL_ALPHA))
	BG = Color(l.get("bg_color", BG), PANEL_ALPHA)
	BG_LIGHT = Color(l.get("bg_light", BG_LIGHT), PANEL_ALPHA)
	TEXT = l.get("text_color", TEXT)
	TEXT_DIM = l.get("text_dim", TEXT_DIM)
	CUT_K = float(l.get("corner_cut", CUT_K))
	BORDER_K = float(l.get("border_width", BORDER_K))
	GLOW_K = float(l.get("glow", GLOW_K))
	BUTTON_FILL = l.get("button_fill", BUTTON_FILL)
	SHEEN = float(l.get("sheen", SHEEN))
	TOOLTIP = l.get("tooltip_color", TOOLTIP)


static func _rebuild() -> void:
	_theme = null
	ThemeDB.get_default_theme().merge_with(build())
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		tree.root.propagate_notification(Control.NOTIFICATION_THEME_CHANGED)
		tree.call_group("neon_restyle", "restyle")
static var TEXT := Color(1.0, 0.89, 0.76)
static var TEXT_DIM := Color(0.78, 0.56, 0.36)
const CUT := 10   # corner cut size (px)
## Customisable (GuiLook / the Library's GUI room): multipliers for every
## box's corner cut, border width and glow; panel opacity; the button fill,
## the top-edge sheen and the tooltip border ("" colour: the highlight).
static var CUT_K := 1.0
static var BORDER_K := 1.0
static var GLOW_K := 1.0
static var PANEL_ALPHA := 0.93
static var BUTTON_FILL := Color(0.05, 0.028, 0.01, 0.92)
static var SHEEN := 0.12
static var TOOLTIP := Color(0, 0, 0, 0)
## The look last applied (apply_look), re-applied over empire palettes.
static var custom := {}

static var _theme: Theme
static var _title_font: Font
static var _heavy_font: Font


## A neon box (see NeonBox): cut corners, a light-to-dark gradient of its own
## colour, a glowing border and a soft glow around it.
static func box(border: Color, bg := BG, width := 2, glow := 6, cut := CUT) -> NeonBox:
	var s := NeonBox.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width = width * BORDER_K
	s.cut = cut * CUT_K
	s.glow = maxf(glow * 0.45, 2.0) * GLOW_K   # a faint glow; highlighted boxes a little more
	s.light = SHEEN
	return s


## A lit box: filled solid with `color` (hovered buttons, the selected tab).
## Text on it: INK.
static func lit(color: Color, width := 1, cut := 7) -> NeonBox:
	var s := box(color, Color(color, 0.95), width, 8, cut)
	s.fill_solid = true
	return s


## A button's resting box: dark, a thin border, the lit rail down its left edge.
static func railed(border: Color, bg := BUTTON_FILL, cut := 7) -> NeonBox:
	var s := box(border, bg, 1, 0, cut)
	s.rail = 3.0
	s.content_margin_left = 16
	return s


## Slanted (parallelogram) button boxes for the big menu buttons.
static func menu_button_styles() -> Dictionary:
	var out := {}
	var defs := {"normal": [Color(CYAN, 0.6), Color(BG, 0.94), 0],
		"hover": [CYAN, Color(CYAN, 0.95), 12],
		"pressed": [PINK, Color(PINK, 0.95), 10],
		"hover_pressed": [PINK, Color(PINK, 0.95), 12],
		"focus": [Color(PINK, 0.9), Color(0, 0, 0, 0), 0],
		"disabled": [Color(DISABLED, 0.4), Color(BG, 0.85), 0]}
	for k in defs:
		var d: Array = defs[k]
		var s := box(d[0], d[1], 1, d[2], 12)
		s.fill_solid = k in ["hover", "pressed", "hover_pressed"]
		s.rail = 4.0 if k == "normal" else 0.0
		s.skew = Vector2(0.28, 0)
		s.content_margin_left = 24
		s.content_margin_right = 24
		if k == "focus":
			s.draw_center = false
		out[k] = s
	return out


## A cut-corner frame: fill, outline, optional inner shape.
static func _frame_icon(w: int, h: int, outline: Array, fill: Color, stroke: Color, inner: Array = [], inner_col := Color(0, 0, 0, 0)) -> ImageTexture:
	var layers := [{"pts": Icons.poly(outline), "fill": fill, "stroke": stroke, "width": 2.0}]
	if not inner.is_empty():
		layers.append({"pts": Icons.poly(inner), "fill": inner_col})
	return Icons.paint(w, h, layers)


## The heavy chrome title font (Noto Sans Black, slanted and emboldened).
static func title_font() -> Font:
	if _title_font == null:
		var base: FontFile = load("res://assets/fonts/NotoSans-Black.ttf")
		var v := FontVariation.new()
		v.base_font = base
		v.variation_embolden = 0.6
		v.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.24, 1), Vector2.ZERO)   # italic slant
		v.spacing_glyph = 2
		_title_font = v
	return _title_font


## Headings, tabs and big buttons: Rajdhani Bold - the squared techno face
## of the reference console (SIL OFL), letter-spaced.
static func heavy_font() -> Font:
	if _heavy_font == null:
		var v := FontVariation.new()
		v.base_font = load("res://assets/fonts/Rajdhani-Bold.ttf")
		v.spacing_glyph = 2
		_heavy_font = v
	return _heavy_font


## A dark background tinted with the highlight colour (hover, selection).
## Greyed-out things (disabled buttons).
static var DISABLED := Color(0.5, 0.42, 0.36)


static func hi_bg(alpha: float, k := 0.16) -> Color:
	return Color(PINK.r * k, PINK.g * k, PINK.b * k, alpha)


## The symbols the UI uses (arrows ▲ ▼ ◀ ▶, ✓ ✕, ●, ─, Greek capitals...)
## that the game's fonts don't have, from two small bundled fonts: without
## them every piece of text holding one asked the system's fontconfig for a
## font that has it - each time it was laid out (a rule card in the Scenario
## Editor: ~60 ms, three quarters of it in fontconfig). Given to the default
## font and to every bundled one, so text finds them before the system.
const SYMBOL_FONTS := ["res://assets/fonts/DejaVuSans-Symbols.ttf", "res://assets/fonts/NotoSansMath-Arrows.ttf"]
static var _fallbacks_done := false

static func install_fallbacks() -> void:
	if _fallbacks_done:
		return
	_fallbacks_done = true
	var syms: Array[Font] = []
	for path in SYMBOL_FONTS:
		var f: Font = load(path)
		if f:
			syms.append(f)
	var fonts: Array = [ThemeDB.fallback_font]
	for path in ["res://assets/fonts/Rajdhani-Bold.ttf", "res://assets/fonts/Rajdhani-SemiBold.ttf", "res://assets/fonts/NotoSans-Black.ttf"]:
		fonts.append(load(path))
	for f in fonts:
		if f is Font and f.fallbacks.is_empty():
			f.fallbacks = syms


static func build() -> Theme:
	install_fallbacks()
	if _theme != null:
		return _theme
	var t := Theme.new()
	_theme = t

	# Buttons (also OptionButton / MenuButton / CheckBox texts).
	# Resting: dark with a thin amber edge and the lit rail; under the mouse
	# the whole button lights up amber (dark ink text); pressed: pale gold.
	var bn := railed(Color(CYAN, 0.6))
	var bh := lit(CYAN)
	bh.content_margin_left = 16
	var bp := lit(PINK)
	bp.content_margin_left = 16
	var bhp := lit(PINK.lightened(0.1))
	bhp.content_margin_left = 16
	var bd := railed(Color(DISABLED, 0.3), Color(BG, 0.6))
	var bf := box(Color(PINK, 0.9), Color(0, 0, 0, 0), 1, 0, 7)
	bf.draw_center = false
	for type in ["Button", "OptionButton", "MenuButton", "ColorPickerButton"]:
		t.set_stylebox("normal", type, bn)
		t.set_stylebox("hover", type, bh)
		t.set_stylebox("pressed", type, bp)
		t.set_stylebox("hover_pressed", type, bhp)
		t.set_stylebox("disabled", type, bd)
		t.set_stylebox("focus", type, bf)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, INK)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_disabled_color", type, Color(DISABLED, 0.7))
		t.set_color("font_outline_color", type, Color(0, 0, 0, 0.0))
		t.set_color("icon_normal_color", type, TEXT)
		t.set_color("icon_hover_color", type, INK)
		t.set_color("icon_pressed_color", type, INK)
		t.set_color("icon_hover_pressed_color", type, INK)

	# Check boxes / toggle switches: transparent, neon icons.
	var clear := StyleBoxEmpty.new()
	clear.content_margin_left = 4
	clear.content_margin_right = 4
	for type in ["CheckBox", "CheckButton"]:
		for k in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			t.set_stylebox(k, type, clear)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, HEAD)
		t.set_color("font_pressed_color", type, TEXT)
		t.set_color("font_hover_pressed_color", type, HEAD)
		t.set_color("font_focus_color", type, TEXT)
	var box := [[5, 2], [20, 2], [20, 17], [17, 20], [2, 20], [2, 5]]
	var check_off := _frame_icon(22, 22, box, Color(BG, 1.0), Color(CYAN, 0.75))
	var check_on := Icons.paint(22, 22, [{"pts": Icons.poly(box), "fill": Color(BG_LIGHT, 1.0), "stroke": CYAN, "width": 2.0},
		{"pts": Icons.poly([[6, 11], [10, 15], [17, 6]]), "closed": false, "stroke": PINK, "width": 3.0}])
	t.set_icon("unchecked", "CheckBox", check_off)
	t.set_icon("checked", "CheckBox", check_on)
	t.set_icon("radio_unchecked", "CheckBox", check_off)
	t.set_icon("radio_checked", "CheckBox", check_on)
	var sw_track := [[8, 2], [44, 2], [44, 16], [38, 22], [2, 22], [2, 8]]
	var sw_off := _frame_icon(46, 24, sw_track, Color(BG, 1.0), Color(CYAN, 0.5), [[8, 6], [18, 6], [18, 18], [6, 18], [6, 8]], Color(DISABLED, 0.8))
	var sw_on := _frame_icon(46, 24, sw_track, hi_bg(1.0, 0.25), CYAN, [[30, 6], [40, 6], [40, 16], [38, 18], [28, 18], [28, 8]], PINK)
	for k in ["checked", "checked_mirrored"]:
		t.set_icon(k, "CheckButton", sw_on)
	for k in ["unchecked", "unchecked_mirrored"]:
		t.set_icon(k, "CheckButton", sw_off)

	# Panels and popups.
	var panel := box(Color(CYAN, 0.55), BG, 1, 6)
	panel.accent = Color(CYAN, 0.9)
	panel.content_margin_left = 0
	panel.content_margin_right = 0
	panel.content_margin_top = 0
	panel.content_margin_bottom = 0
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("panel", "PanelContainer", panel)
	var pop := box(Color(CYAN, 0.7), Color(BG, 0.97), 1, 6, 6)
	pop.content_margin_top = 6
	pop.content_margin_bottom = 6
	t.set_stylebox("panel", "PopupMenu", pop)
	t.set_stylebox("panel", "PopupPanel", pop)
	t.set_stylebox("panel", "TooltipPanel", box(Color(TOOLTIP if TOOLTIP.a > 0.0 else CYAN, 0.8), Color(BG, 0.97), 1, 4, 5))
	t.set_color("font_color", "TooltipLabel", TEXT)
	var pop_hover := lit(CYAN, 1, 4)
	pop_hover.content_margin_left = 4
	t.set_stylebox("hover", "PopupMenu", pop_hover)
	var sep := StyleBoxLine.new()
	sep.color = Color(CYAN, 0.3)
	sep.thickness = 1
	t.set_stylebox("separator", "PopupMenu", sep)
	var lsep := StyleBoxLine.new()
	lsep.color = Color(PINK, 0.5)
	lsep.thickness = 1
	t.set_stylebox("labeled_separator_left", "PopupMenu", lsep)
	t.set_stylebox("labeled_separator_right", "PopupMenu", lsep)
	t.set_color("font_color", "PopupMenu", TEXT)
	t.set_color("font_disabled_color", "PopupMenu", Color(TEXT_DIM, 0.6))
	t.set_constant("v_separation", "PopupMenu", 10)
	t.set_constant("item_start_padding", "PopupMenu", 14)
	t.set_constant("item_end_padding", "PopupMenu", 18)
	t.set_constant("h_separation", "PopupMenu", 8)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_separator_color", "PopupMenu", TEXT_DIM)

	# Text fields.
	var le := box(Color(CYAN, 0.35), Color(BG.darkened(0.3), 0.95), 1, 0, 6)
	var lef := box(PINK, Color(BG_LIGHT, 0.98), 1, 6, 6)
	for type in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", type, le)
		t.set_stylebox("focus", type, lef)
		t.set_stylebox("read_only", type, le)
		t.set_color("font_color", type, TEXT)
		t.set_color("caret_color", type, PINK)
		t.set_color("selection_color", type, Color(PINK, 0.35))
		t.set_color("font_placeholder_color", type, Color(TEXT_DIM, 0.6))

	# Sliders: thin neon track, diamond grabber.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(BG_LIGHT, 0.9)
	track.border_color = Color(CYAN, 0.3)
	track.set_border_width_all(1)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(CYAN, 0.75)
	fill.shadow_color = Color(CYAN, 0.35)
	fill.shadow_size = 4
	fill.content_margin_top = 3
	fill.content_margin_bottom = 3
	var fill_hi := fill.duplicate()
	fill_hi.bg_color = PINK
	fill_hi.shadow_color = Color(PINK, 0.4)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hi)
	var diamond := [[11, 1], [21, 11], [11, 21], [1, 11]]
	var gem := [[11, 6], [16, 11], [11, 16], [6, 11]]
	var grab := _frame_icon(22, 22, diamond, Color(BG, 1.0), CYAN, gem, CYAN)
	var grab_hi := _frame_icon(22, 22, diamond, hi_bg(1.0, 0.18), PINK, gem, PINK)
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab_hi)

	# Scroll bars.
	for type in ["VScrollBar", "HScrollBar"]:
		var sc := StyleBoxFlat.new()
		sc.bg_color = Color(BG, 0.7)
		sc.border_color = Color(CYAN, 0.2)
		sc.set_border_width_all(1)
		sc.content_margin_left = 5
		sc.content_margin_right = 5
		sc.content_margin_top = 5
		sc.content_margin_bottom = 5
		var g := StyleBoxFlat.new()
		g.bg_color = Color(CYAN, 0.6)
		g.corner_radius_top_left = 4
		g.corner_radius_bottom_right = 4
		g.corner_detail = 1
		var gh := g.duplicate()
		gh.bg_color = PINK
		gh.shadow_color = Color(PINK, 0.4)
		gh.shadow_size = 4
		t.set_stylebox("scroll", type, sc)
		t.set_stylebox("scroll_focus", type, sc)
		t.set_stylebox("grabber", type, g)
		t.set_stylebox("grabber_highlight", type, gh)
		t.set_stylebox("grabber_pressed", type, gh)

	# Lists and trees.
	var lst := box(Color(CYAN, 0.35), Color(BG.darkened(0.3), 0.9), 1, 0, 6)
	var sel := lit(Color(CYAN, 0.85), 1, 4)
	var sel_f := lit(CYAN, 1, 4)
	for type in ["ItemList", "Tree"]:
		t.set_stylebox("panel", type, lst)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_stylebox("selected", type, sel)
		t.set_stylebox("selected_focus", type, sel_f)
		t.set_stylebox("cursor", type, StyleBoxEmpty.new())
		t.set_stylebox("cursor_unfocused", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_selected_color", type, INK)
		t.set_color("font_hovered_color", type, HEAD)
	var hov := box(Color(CYAN, 0.4), hi_bg(0.6, 0.2), 1, 0, 4)
	t.set_stylebox("hovered", "ItemList", hov)
	t.set_stylebox("hovered", "Tree", hov)
	t.set_color("guide_color", "Tree", Color(CYAN, 0.12))
	t.set_color("relationship_line_color", "Tree", Color(CYAN, 0.25))
	t.set_stylebox("title_button_normal", "Tree", box(Color(CYAN, 0.4), BG_LIGHT, 1, 0, 4))

	# Progress bars and tabs (TabContainer / TabBar, where used).
	var pbg := StyleBoxFlat.new()
	pbg.bg_color = Color(BG_LIGHT, 0.9)
	pbg.border_color = Color(CYAN, 0.35)
	pbg.set_border_width_all(1)
	pbg.corner_radius_top_left = 5
	pbg.corner_radius_bottom_right = 5
	pbg.corner_detail = 1
	var pfill := pbg.duplicate()
	pfill.bg_color = CYAN
	pfill.border_color = Color(1, 1, 1, 0.35)
	pfill.shadow_color = Color(CYAN, 0.35)
	pfill.shadow_size = 4
	t.set_stylebox("background", "ProgressBar", pbg)
	t.set_stylebox("fill", "ProgressBar", pfill)
	t.set_stylebox("tab_selected", "TabContainer", lit(CYAN, 1, 6))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(CYAN, 0.4), BG, 1, 0, 6))
	t.set_stylebox("tab_hovered", "TabContainer", box(CYAN, hi_bg(0.9, 0.25), 1, 4, 6))
	t.set_color("font_selected_color", "TabContainer", INK)
	t.set_color("font_hovered_color", "TabContainer", HEAD)
	t.set_color("font_unselected_color", "TabContainer", TEXT_DIM)
	t.set_stylebox("panel", "TabContainer", panel)

	# Labels: default text colour and a faint dark outline for legibility.
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", Color(0, 0, 0, 0.5))
	return t
