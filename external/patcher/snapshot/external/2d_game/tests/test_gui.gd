extends TestCase
## The GUI keeps one look everywhere (the reference console: teal glass,
## cyan borders, orange highlights) - it no longer follows the empire.


func teardown() -> void:
	NeonTheme.set_empire("")


func test_one_palette_everywhere() -> void:
	var main := NeonTheme.CYAN
	for e in ["", "minoa", "athens", "sparta", "mycenae", "pirates"]:
		NeonTheme.set_empire(e)
		check_eq(NeonTheme.empire, "", e + ": no empire palette")
		check(NeonTheme.CYAN.is_equal_approx(main), e + ": the same main colour")
		var box := ThemeDB.get_default_theme().get_stylebox("panel", "PanelContainer") as NeonBox
		check(box != null, e + ": panel style is a NeonBox")
		if box:
			check(box.border_color.is_equal_approx(Color(NeonTheme.CYAN, box.border_color.a)), e + ": panel border in the main colour")
			check(box.accent.is_equal_approx(Color(NeonTheme.CYAN, box.accent.a)) and box.accent.a > 0.5, e + ": bracket corners and hatch in the main colour")
	check(NeonTheme.CYAN.r > 0.9 and NeonTheme.CYAN.g > 0.35 and NeonTheme.CYAN.g < 0.65 and NeonTheme.CYAN.b < 0.25, "the main colour is amber")
	check(NeonTheme.INFO.b > NeonTheme.INFO.r + 0.3, "the second colour is steel blue")
	check(UI.panel_style(Color.RED).border_color.is_equal_approx(Color(NeonTheme.CYAN, 0.7)), "code-built panels: the theme's border, whatever was asked")


## The Helm look: buttons rest dark with a lit rail and light up solid amber
## (ink-dark text) under the mouse; the selected tab is lit too.
func test_helm_buttons_and_tabs() -> void:
	NeonTheme.apply_look({})
	var t := ThemeDB.get_default_theme()
	var normal := t.get_stylebox("normal", "Button") as NeonBox
	var hover := t.get_stylebox("hover", "Button") as NeonBox
	check(normal != null and normal.rail > 0.0 and not normal.fill_solid, "a resting button: dark, with the rail")
	check(hover != null and hover.fill_solid, "a hovered button lights up")
	check(t.get_color("font_hover_color", "Button").get_luminance() < 0.2, "dark ink text on it")
	var bar := UI.tab_bar(["A", "B"], func(_i): pass)
	var sel := (bar.get_child(0) as Button).get_theme_stylebox("pressed") as NeonBox
	check(sel != null and sel.fill_solid, "the selected tab is lit")
	bar.free()
	var sec := UI.section("HEADING")
	check(sec.get_theme_color("font_color").is_equal_approx(NeonTheme.HEAD), "section headings in the heading amber")
	sec.free()


func test_minoan_portraits() -> void:
	for sp in ["gunner", "archer", "android"]:
		check(ProcArt.has_sprite("npc_minoan_%s_portrait" % sp), "traced portrait for " + sp)
		var p := Portrait.new().setup("t-" + sp, "minoa", sp)
		check(p._minoan_tex != null, "Minoan contact uses the traced portrait: " + sp)
		check(p.person_name != "", "Minoan name")
		p.free()
	var o := Portrait.new().setup("someone", "athens")
	check(o._minoan_tex == null, "other empires keep their own portraits")
	o.free()
	var f := Portrait.new().setup("x", "minoa", "archer")
	check(f.person_name in Portrait.MINOAN_FEMALE_NAMES, "the archer gets a female name")
	f.free()
