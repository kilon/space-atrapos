extends TestCase
## The game's typeface and its text sizes: Atrapos Sans (tools/make_font.py)
## is the font everywhere - the theme's default, ThemeDB's fallback (what
## code-drawn text uses), the headings - and it has the letters the game's
## texts use; and no text is ever under 14 px (Settings.MIN_FONT): the shared
## helpers clamp, and no script or scene asks for a smaller size.

const REGULAR := "res://assets/fonts/AtraposSans-Regular.ttf"
const BOLD := "res://assets/fonts/AtraposSans-Bold.ttf"


func test_atrapos_sans_everywhere() -> void:
	var t := NeonTheme.build()
	check(t.default_font != null and t.default_font.resource_path == REGULAR, "the theme's default font is Atrapos Sans Regular")
	check(ThemeDB.fallback_font == NeonTheme.body_font(), "ThemeDB's fallback font (code-drawn text) is it too")
	check(NeonTheme.heavy_font().resource_path == BOLD, "headings: Atrapos Sans Bold")
	var tf := NeonTheme.title_font() as FontVariation
	check(tf != null and tf.base_font.resource_path == BOLD, "the title: Atrapos Sans Bold")
	check(t.get_font("bold_font", "RichTextLabel") == NeonTheme.heavy_font(), "[b] in rich text: the Bold")
	check(not NeonTheme.body_font().fallbacks.is_empty(), "symbols it lacks come from the bundled fallbacks")
	# Every letter and the usual marks the game's texts use, from the face itself.
	var f: Font = NeonTheme.body_font()
	var missing := ""
	for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,:;!?'\"“”‘’()[]{}/\\|_-+=<>°%&*@#€£$~^`·•×–—−›‹…µëéèêàáâäöüçñßΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρσςτυφχψωάέήίόύώ":
		if not (f as FontFile).has_char(ch.unicode_at(0)):
			missing += ch
	check(missing == "", "Atrapos Sans has every letter the game uses (missing: %s)" % missing)


func test_helpers_never_under_14() -> void:
	var m := Settings.MIN_FONT
	check_eq(m, 14, "the smallest text size is 14 px")
	var l := UI.label("x", 8)
	check(l.get_theme_font_size("font_size") >= m, "UI.label clamps (asked 8, got %d)" % l.get_theme_font_size("font_size"))
	var n := UI.note("x", 9)
	check(n.get_theme_font_size("font_size") >= m, "UI.note clamps")
	var b := UI.button("x", func(): pass, 10)
	check(b.get_theme_font_size("font_size") >= m, "UI.button clamps")
	for cat in ["hud", "menu", "world"]:
		check(Settings.fs(cat, 6) >= m, "Settings.fs(%s) clamps" % cat)
	l.free()
	n.free()
	b.free()


## A size under 14 written into a script or a scene: font size overrides,
## the helpers' size arguments, Settings.fs, draw_string's size.
func test_no_literal_text_under_14() -> void:
	var pats := [
		'font_size_override\\("[a-z_]+",\\s*(\\d+)\\)',
		'font_sizes/[a-z_]+\\s*=\\s*(\\d+)\\b',
		'Settings\\.fs\\("[a-z]+",\\s*(\\d+)\\)',
		'UI\\.(?:label|note)\\((?:"(?:[^"\\\\]|\\\\.)*"|[^,()"]+(?:\\([^()]*\\))?)(?:\\s*%\\s*(?:\\[[^\\]]*\\]|[^,()]+(?:\\([^()]*\\))?))?,\\s*(\\d+)\\s*[,)]',
		'draw_(?:string|string_outline|multiline_string)\\(.*HORIZONTAL_ALIGNMENT_[A-Z]+,\\s*[^,]+,\\s*(\\d+)\\s*[,)]',
		'\\bfont_size\\s*=\\s*(\\d+)\\b',
	]
	var res: Array[RegEx] = []
	for p in pats:
		var r := RegEx.new()
		check(r.compile(p) == OK, "pattern compiles: %s" % p)
		res.append(r)
	var bad: Array = []
	for path in _files("res://scripts", ".gd") + _files("res://scenes", ".tscn"):
		var lines := FileAccess.get_file_as_string(path).split("\n")
		for i in lines.size():
			for r in res:
				for mt in r.search_all(lines[i]):
					var v := int(mt.get_string(1))
					if v > 0 and v < Settings.MIN_FONT:
						bad.append("%s:%d (%d)" % [path.trim_prefix("res://"), i + 1, v])
	check(bad.is_empty(), "no text under 14 px: %s" % ", ".join(bad))


func _files(dir: String, ext: String) -> Array:
	var out := []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(ext):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out += _files(dir.path_join(sub), ext)
	return out
