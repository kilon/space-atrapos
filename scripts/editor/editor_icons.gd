class_name EditorIcons
## Icons for the editor screens (the data editor, the zoo, the level editor),
## painted once (Icons.paint) and cached, plus the tooltip format they share:
## a title, the shortcut in brackets, and a description.

static var _cache := {}
const W := Color(1.0, 0.92, 0.82)
const BLUE := Color(1.0, 0.6, 0.2)        # (the GUI's main colour - amber; the name is older)
const GOLD := Color(1.0, 0.84, 0.5)       # (the GUI's highlight - pale gold)
const GLOW := Color(1.0, 0.6, 0.2, 0.28)
const RED := Color(1.0, 0.4, 0.35)
const GREEN := Color(0.45, 1.0, 0.55)


## "Title      [keys]\nbody"
static func tip(title: String, keys: String, body: String) -> String:
	return title + ("      [" + keys + "]" if keys != "" else "") + "\n" + body


static func _l(pts: Array, w := 1.8, col := W) -> Dictionary:
	return {"pts": Icons.poly(pts), "stroke": col, "width": w, "closed": false}


static func _f(pts: Array, col := W) -> Dictionary:
	return {"pts": Icons.poly(pts), "fill": col}


static func _c(c: Vector2, r: float, col := W) -> Dictionary:
	return {"pts": Icons.arc(c, r, 0, TAU, 20), "fill": col}


static func _ring(c: Vector2, r: float, w := 1.6, col := W) -> Dictionary:
	return {"pts": Icons.arc(c, r, 0, TAU, 24), "stroke": col, "width": w, "fill": Color(0, 0, 0, 0)}


## A glowing line (the reference console's line icons): a soft wide stroke
## under a thin bright one.
static func _gl(pts: Array, w := 1.7, col := BLUE, closed := false) -> Array:
	return [{"pts": Icons.poly(pts), "stroke": Color(col, 0.28), "width": w + 2.6, "closed": closed},
		{"pts": Icons.poly(pts), "stroke": col.lightened(0.15), "width": w, "closed": closed}]


static func _gring(c: Vector2, r: float, w := 1.6, col := BLUE, a0 := 0.0, a1 := TAU) -> Array:
	var pts := Icons.arc(c, r, a0, a1, 28)
	var arr := []
	for q in pts:
		arr.append([q.x, q.y])
	return _gl(arr, w, col)


## The icon called `name` (20 x 20; null for unknown names).
static func get_icon(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var layers := layers_of(name)
	if layers.is_empty():
		return null
	_cache[name] = Icons.paint(20, 20, layers)
	return _cache[name]


## Every icon's name (warm(): painted ahead, in the background).
const NAMES := ["ui_industry", "ui_journal", "ui_cargo", "ui_tech", "ui_codex", "ui_guide", "ui_system", "ui_galaxy", "save", "reload", "undo", "redo", "paste", "gui", "back", "forward", "exit", "add", "up", "down", "delete", "play", "stop", "anim", "library", "zoo", "dialogue", "quest", "lore", "chat", "sprites", "characters", "ships", "stations", "planets", "nebulae", "suns", "buildings", "effects", "terrain", "building", "wall", "column", "npc", "prop", "erase", "enemy", "neutral", "asteroid", "tool", "buy", "sell", "sellall", "accept", "turnin", "abandon", "undock", "pledge", "repair", "remove", "apply", "paint", "close", "land", "next", "skip", "restart", "menu", "rating", "ship", "bake", "fit_all", "duplicate", "rename", "key", "keypose", "keydel", "prevkey", "nextkey", "docs", "help", "patch", "mesh", "mod", "select", "node", "rect", "ellipse", "star_tool", "pen", "pencil", "text", "picker", "export", "open", "new", "grid", "eye", "eye_off", "lock", "unlock", "snap"] + MESH_ICONS


## Paints every icon not yet on disk, on worker threads - at start-up, so no
## screen waits for its icons the first time it opens (Icons.warm).
static func warm() -> void:
	if DisplayServer.get_name() == "headless":
		return   # (no screen: nothing to paint for - and no threads left running at exit)
	for n in NAMES:
		Icons.warm(20, 20, layers_of(n))


## What icon `name` is drawn with ([] for unknown names).
static func layers_of(name: String) -> Array:
	if name.begins_with("m_cv_"):   # (the Curve modeling tab's: their own file)
		return (load("res://scripts/editor/mesh/curve_icons.gd") as GDScript).call("layers", name)
	if name.begins_with("m_"):
		return _mesh_icon(name)
	var layers: Array = []
	match name:
		# The Automaton's tabs: glowing line icons, one per page.
		"ui_journal":   # the quest journal: a log book with a bookmark
			layers = _gl([[4, 2], [16, 2], [16, 18], [4, 18]], 1.6, BLUE, true) + _gl([[7, 6], [13, 6]], 1.3) + _gl([[7, 9.5], [13, 9.5]], 1.3) + _gl([[7, 13], [11, 13]], 1.3) \
				+ [_f([[12, 2], [15, 2], [15, 8], [13.5, 6.5], [12, 8]], GOLD)]
		"ui_cargo":     # the hold: a cargo crate
			layers = _gl([[3, 6], [10, 3], [17, 6], [17, 15], [10, 18], [3, 15]], 1.6, BLUE, true) + _gl([[3, 6], [10, 9], [17, 6]], 1.4) + _gl([[10, 9], [10, 18]], 1.4) \
				+ _gl([[6.5, 4.5], [13.5, 7.5]], 1.2, GOLD)
		"ui_tech":      # research: a circuit tree of nodes
			layers = _gl([[10, 4], [10, 9], [5, 13], [5, 16]], 1.5) + _gl([[10, 9], [15, 13], [15, 16]], 1.5) + _gl([[10, 9], [10, 16]], 1.5) \
				+ [_c(Vector2(10, 3.5), 2.2, GOLD), _c(Vector2(5, 16.5), 1.9, BLUE), _c(Vector2(10, 16.5), 1.9, BLUE), _c(Vector2(15, 16.5), 1.9, BLUE)]
		"ui_codex":     # the encyclopedia: an open book
			layers = _gl([[10, 5], [6, 3], [2, 4], [2, 16], [6, 15], [10, 17], [14, 15], [18, 16], [18, 4], [14, 3], [10, 5], [10, 17]], 1.5) \
				+ _gl([[4.5, 7], [7.5, 6.3]], 1.1) + _gl([[12.5, 6.3], [15.5, 7]], 1.1) + _gl([[4.5, 10], [7.5, 9.3]], 1.1) + _gl([[12.5, 9.3], [15.5, 10]], 1.1)
		"ui_industry":  # industry: a factory with a smoking stack and a gear
			layers = _gl([[2, 18], [2, 9], [7, 12], [7, 9], [12, 12], [12, 3], [16, 3], [16, 18], [2, 18]], 1.5, BLUE, true) \
				+ _gring(Vector2(7, 15), 1.8, 1.2, GOLD) + [_c(Vector2(14, 1.5), 1.1, Color(GOLD, 0.7)), _c(Vector2(17, 0.8), 0.8, Color(GOLD, 0.45))]
		"ui_guide":     # how to play: an info badge
			layers = _gring(Vector2(10, 10), 7.5, 1.6) + [_c(Vector2(10, 6), 1.5, GOLD)] + _gl([[10, 9], [10, 15]], 2.0, W)
		"ui_system":    # the system map: a planet, its orbit and a moon
			layers = _gring(Vector2(10, 10), 8.0, 1.0, Color(BLUE, 0.7)) + [_c(Vector2(10, 10), 4.0, BLUE), _c(Vector2(16.5, 5.5), 1.8, GOLD)]
		"ui_galaxy":    # the galaxy map: a two-armed spiral
			var arm1 := []
			var arm2 := []
			for k in 14:
				var a := k * 0.42
				var r := 1.2 + k * 0.62
				arm1.append([10 + cos(a) * r, 10 + sin(a) * r * 0.8])
				arm2.append([10 - cos(a) * r, 10 - sin(a) * r * 0.8])
			layers = _gl(arm1, 1.5) + _gl(arm2, 1.5) + [_c(Vector2(10, 10), 2.0, GOLD)]
		"save": layers = [_f([[2, 2], [15, 2], [18, 5], [18, 18], [2, 18]], BLUE), _f([[5, 2], [14, 2], [14, 8], [5, 8]], Color(0.1, 0.12, 0.18)), _f([[5, 11], [15, 11], [15, 17], [5, 17]], W)]
		"reload": layers = [{"pts": Icons.arc(Vector2(10, 10), 6.5, -PI * 0.2, PI * 1.5, 16), "stroke": W, "width": 2.0, "closed": false}, _f([[16, 1], [17, 8], [10, 5]])]
		"undo": layers = [{"pts": Icons.arc(Vector2(11, 11), 6.0, PI * 1.1, PI * 2.25, 14), "stroke": W, "width": 2.0, "closed": false}, _f([[1, 9], [8, 5], [8, 13]])]
		"redo": layers = [{"pts": Icons.arc(Vector2(9, 11), 6.0, PI * 0.75, PI * 1.9, 14), "stroke": W, "width": 2.0, "closed": false}, _f([[19, 9], [12, 5], [12, 13]])]
		"paste": layers = [_f([[4, 4], [16, 4], [16, 19], [4, 19]], BLUE), _f([[7, 2], [13, 2], [13, 6], [7, 6]], GOLD), _l([[7, 10], [13, 10]], 1.3, Color(0.1, 0.12, 0.18)), _l([[7, 14], [13, 14]], 1.3, Color(0.1, 0.12, 0.18))]
		"gui": layers = [_l([[2, 3], [18, 3], [18, 17], [2, 17], [2, 3]], 1.6), _f([[2, 3], [18, 3], [18, 7], [2, 7]], BLUE), _f([[5, 10], [11, 10], [11, 14], [5, 14]], GOLD), _l([[13, 11], [16, 11]], 1.4, GREEN), _l([[13, 14], [16, 14]], 1.4, GREEN)]
		"back": layers = [_f([[2, 10], [10, 3], [10, 7], [18, 7], [18, 13], [10, 13], [10, 17]])]
		"forward": layers = [_f([[18, 10], [10, 3], [10, 7], [2, 7], [2, 13], [10, 13], [10, 17]])]
		"exit": layers = [_l([[8, 3], [3, 3], [3, 17], [8, 17]], 2.0), _f([[19, 10], [13, 5], [13, 8], [7, 8], [7, 12], [13, 12], [13, 15]], RED)]
		"add": layers = [_f([[8, 3], [12, 3], [12, 8], [17, 8], [17, 12], [12, 12], [12, 17], [8, 17], [8, 12], [3, 12], [3, 8], [8, 8]], GREEN)]
		"up": layers = [_f([[10, 4], [17, 14], [3, 14]])]
		"down": layers = [_f([[10, 16], [17, 6], [3, 6]])]
		"delete": layers = [_l([[4, 4], [16, 16]], 2.6, RED), _l([[16, 4], [4, 16]], 2.6, RED)]
		"play": layers = [_f([[5, 3], [17, 10], [5, 17]], GREEN)]
		"stop": layers = [_f([[4, 4], [16, 4], [16, 16], [4, 16]], RED)]
		"anim": layers = [_l([[2, 14], [18, 14]], 1.4, BLUE), _f([[5, 10], [8, 14], [5, 18], [2, 14]], GOLD), _f([[15, 10], [18, 14], [15, 18], [12, 14]], GOLD),
			_l([[4, 7], [9, 3], [14, 6]], 1.8), _c(Vector2(9, 3), 1.8)]
		# The Library (every asset of the game): a shelf of books - spines of
		# different heights and colours, one leaning on the others.
		"library": layers = [_f([[2, 5], [5.5, 5], [5.5, 17], [2, 17]], BLUE), _l([[2, 8], [5.5, 8]], 1.0, Color(0.1, 0.12, 0.18)), _l([[2, 14], [5.5, 14]], 1.0, Color(0.1, 0.12, 0.18)),
			_f([[6.5, 2.5], [10, 2.5], [10, 17], [6.5, 17]], GOLD), _l([[6.5, 6], [10, 6]], 1.0, Color(0.1, 0.12, 0.18)), _c(Vector2(8.25, 11), 1.1, Color(0.1, 0.12, 0.18)),
			_f([[11, 6], [13.5, 6], [13.5, 17], [11, 17]], W), _l([[11, 9], [13.5, 9]], 1.0, Color(0.1, 0.12, 0.18)),
			_f([[14.2, 17], [16.9, 17], [19.2, 6.6], [16.6, 5.9]], Color(0.45, 0.75, 1.0)),
			_l([[1, 18.4], [19, 18.4]], 1.6)]
		"zoo": layers = [_c(Vector2(10, 12), 5.0), _c(Vector2(4.5, 6), 2.4), _c(Vector2(8, 3.5), 2.2), _c(Vector2(12, 3.5), 2.2), _c(Vector2(15.5, 6), 2.4)]
		"dialogue": layers = [_f([[2, 3], [18, 3], [18, 13], [9, 13], [5, 17], [6, 13], [2, 13]], BLUE), _l([[5, 7], [15, 7]], 1.3, Color(0.1, 0.12, 0.18)), _l([[5, 10], [12, 10]], 1.3, Color(0.1, 0.12, 0.18))]
		"quest": layers = [_l([[4, 2], [4, 18]], 2.0), _f([[5, 3], [17, 5], [12, 8], [17, 11], [5, 11]], GOLD)]
		"lore": layers = [_f([[2, 4], [9, 3], [10, 5], [10, 17], [9, 15], [2, 16]], BLUE), _f([[18, 4], [11, 3], [10, 5], [10, 17], [11, 15], [18, 16]], W)]
		"chat": layers = [_f([[1, 3], [12, 3], [12, 10], [6, 10], [3, 13], [4, 10], [1, 10]], BLUE), _f([[8, 8], [19, 8], [19, 15], [16, 15], [17, 18], [13, 15], [8, 15]], GOLD)]
		"sprites": layers = [_l([[2, 3], [18, 3], [18, 17], [2, 17], [2, 3]], 1.6), _f([[3, 16], [8, 9], [11, 13], [14, 10], [17, 16]], GREEN), _c(Vector2(13, 7), 1.8, GOLD)]
		"characters": layers = [_c(Vector2(10, 5), 3.2), _f([[4, 18], [6, 10], [14, 10], [16, 18]])]
		"ships": layers = [_f([[10, 1], [15, 16], [10, 13], [5, 16]], BLUE), _f([[8, 17], [12, 17], [10, 20]], Color(1.0, 0.6, 0.3))]
		"stations": layers = [_ring(Vector2(10, 10), 7.0, 2.0, BLUE), _l([[10, 1], [10, 19]], 1.6), _l([[1, 10], [19, 10]], 1.6), _c(Vector2(10, 10), 2.6, GOLD)]
		"planets": layers = [_c(Vector2(10, 10), 5.5, Color(0.45, 0.75, 1.0)), {"pts": Icons.poly([[1, 13], [5, 9], [19, 7], [15, 11]]), "stroke": GOLD, "width": 1.4}]
		"nebulae": layers = [_c(Vector2(7, 9), 5.5, Color(0.85, 0.3, 0.6)), _c(Vector2(13, 11), 5.0, Color(0.35, 0.55, 1.0)), _c(Vector2(10, 9), 2.2, Color(1.0, 0.92, 0.85))]
		"suns": layers = [_l([[10, 1], [10, 19]], 1.4, GOLD), _l([[1, 10], [19, 10]], 1.4, GOLD), _l([[4, 4], [16, 16]], 1.4, GOLD), _l([[16, 4], [4, 16]], 1.4, GOLD),
			_c(Vector2(10, 10), 5.5, Color(1.0, 0.7, 0.25)), _c(Vector2(10, 10), 3.0, Color(1.0, 0.93, 0.6))]
		"buildings": layers = [_f([[2, 9], [10, 3], [18, 9]], RED), _f([[4, 9], [16, 9], [16, 18], [4, 18]], W), _f([[8, 12], [12, 12], [12, 18], [8, 18]], Color(0.3, 0.35, 0.45))]
		"effects": layers = [_f([[10, 1], [12, 8], [19, 10], [12, 12], [10, 19], [8, 12], [1, 10], [8, 8]], GOLD)]
		"terrain": layers = [_l([[3, 17], [11, 9]], 3.0, Color(0.75, 0.55, 0.35)), _f([[11, 9], [17, 3], [19, 5], [13, 11]], GREEN)]
		"building": layers = [_f([[2, 9], [10, 3], [18, 9]], RED), _f([[4, 9], [16, 9], [16, 18], [4, 18]], W)]
		"wall": layers = [_f([[2, 4], [18, 4], [18, 17], [2, 17]], Color(0.9, 0.75, 0.55)), _l([[2, 8], [18, 8]], 1.0, Color(0.4, 0.3, 0.2)), _l([[2, 12.5], [18, 12.5]], 1.0, Color(0.4, 0.3, 0.2)),
			_l([[10, 4], [10, 8]], 1.0, Color(0.4, 0.3, 0.2)), _l([[6, 8], [6, 12.5]], 1.0, Color(0.4, 0.3, 0.2)), _l([[14, 8], [14, 12.5]], 1.0, Color(0.4, 0.3, 0.2))]
		"column": layers = [_f([[5, 2], [15, 2], [15, 5], [5, 5]], Color(0.2, 0.2, 0.22)), _f([[7, 5], [13, 5], [12, 17], [8, 17]], RED), _f([[5, 17], [15, 17], [15, 19], [5, 19]], GOLD)]
		"npc": layers = [_c(Vector2(10, 5), 3.2, GOLD), _f([[4, 18], [6, 10], [14, 10], [16, 18]], RED)]
		"prop": layers = [_f([[9, 13], [11, 13], [11, 19], [9, 19]], Color(0.55, 0.38, 0.22)), _c(Vector2(10, 8), 6.0, GREEN)]
		"erase": layers = [_f([[3, 13], [11, 5], [17, 11], [9, 19]], Color(1.0, 0.55, 0.65)), _f([[3, 13], [7, 9], [13, 15], [9, 19]], W)]
		"enemy": layers = [_f([[10, 1], [16, 17], [10, 13], [4, 17]], RED)]
		"neutral": layers = [_f([[10, 1], [16, 17], [10, 13], [4, 17]], BLUE)]
		"asteroid": layers = [_f([[4, 6], [10, 2], [17, 5], [18, 12], [12, 18], [4, 15], [2, 10]], Color(0.6, 0.55, 0.5))]
		"tool": layers = [_c(Vector2(10, 10), 4.0, BLUE)]
		"buy": layers = [_l([[1, 3], [4, 3], [6, 13], [16, 13], [18, 6], [5, 6]], 1.8), _c(Vector2(7, 17), 1.6), _c(Vector2(15, 17), 1.6), _f([[10, 7], [12, 7], [12, 9], [14, 9], [14, 11], [12, 11], [12, 13], [10, 13], [10, 11], [8, 11], [8, 9], [10, 9]], GREEN)]
		"sell": layers = [_c(Vector2(10, 10), 7.5, GOLD), _ring(Vector2(10, 10), 5.0, 1.2, Color(0.55, 0.4, 0.1)), _f([[9, 6], [11, 6], [11, 14], [9, 14]], Color(0.55, 0.4, 0.1))]
		"sellall": layers = [_c(Vector2(7, 12), 5.5, Color(0.85, 0.65, 0.2)), _c(Vector2(13, 8), 5.5, GOLD), _ring(Vector2(13, 8), 3.5, 1.0, Color(0.55, 0.4, 0.1))]
		"accept": layers = [_l([[3, 10], [8, 15], [17, 4]], 3.0, GREEN)]
		"turnin": layers = [_f([[3, 4], [17, 4], [17, 17], [3, 17]], Color(0.25, 0.3, 0.4)), _l([[5, 10], [9, 14], [16, 6]], 2.6, GOLD)]
		"abandon": layers = [_ring(Vector2(10, 10), 7.5, 2.0, RED), _l([[5, 15], [15, 5]], 2.2, RED)]
		"undock": layers = [_ring(Vector2(7, 10), 5.0, 1.6, BLUE), _f([[19, 10], [12, 5], [12, 8], [8, 8], [8, 12], [12, 12], [12, 15]], GOLD)]
		"pledge": layers = [_l([[4, 2], [4, 18]], 2.0), _f([[5, 3], [17, 3], [14, 7], [17, 11], [5, 11]], RED), _c(Vector2(10, 7), 1.6, GOLD)]
		"repair": layers = [_l([[4, 16], [12, 8]], 3.0, Color(0.7, 0.75, 0.8)), _ring(Vector2(14, 6), 3.5, 2.4, Color(0.7, 0.75, 0.8))]
		"remove": layers = [_f([[3, 9], [17, 9], [17, 12], [3, 12]], RED)]
		"apply": layers = [_f([[3, 3], [13, 3], [13, 8], [3, 8]], Color(0.9, 0.4, 0.5)), _l([[8, 8], [8, 11], [11, 11], [11, 18]], 2.2), _l([[11, 13], [18, 6]], 2.0, GREEN)]
		"paint": layers = [_f([[3, 17], [6, 11], [10, 15]], Color(0.9, 0.4, 0.5)), _l([[8, 13], [17, 3]], 2.6, Color(0.75, 0.55, 0.35))]
		"close": layers = [_l([[4, 4], [16, 16]], 2.6, W), _l([[16, 4], [4, 16]], 2.6, W)]
		"land": layers = [_c(Vector2(10, 14), 6.0, Color(0.45, 0.75, 1.0)), _f([[10, 1], [13, 6], [11, 6], [11, 10], [9, 10], [9, 6], [7, 6]], GOLD)]
		"next": layers = [_f([[4, 3], [14, 10], [4, 17]]), _f([[14, 3], [17, 3], [17, 17], [14, 17]])]
		"skip": layers = [_f([[2, 4], [9, 10], [2, 16]]), _f([[10, 4], [17, 10], [10, 16]])]
		"restart": layers = [{"pts": Icons.arc(Vector2(10, 10), 6.5, PI * 0.2, PI * 1.9, 16), "stroke": GREEN, "width": 2.2, "closed": false}, _f([[2, 2], [9, 3], [3, 9]], GREEN)]
		"menu": layers = [_f([[3, 4], [17, 4], [17, 6.5], [3, 6.5]]), _f([[3, 9], [17, 9], [17, 11.5], [3, 11.5]]), _f([[3, 14], [17, 14], [17, 16.5], [3, 16.5]])]
		"rating": layers = [_f([[10, 2], [12.4, 7.5], [18, 8], [13.7, 11.8], [15, 17.5], [10, 14.5], [5, 17.5], [6.3, 11.8], [2, 8], [7.6, 7.5]], GOLD)]
		"ship": layers = [_f([[10, 1], [15, 16], [10, 13], [5, 16]], BLUE)]
		"bake": layers = [_f([[3, 8], [17, 8], [17, 18], [3, 18]], Color(0.55, 0.6, 0.7)), _f([[5, 11], [15, 11], [15, 16], [5, 16]], Color(0.12, 0.1, 0.1)),
			_f([[8, 16], [10, 12], [12, 16]], Color(1.0, 0.55, 0.15)), _f([[9, 16], [10, 14], [11, 16]], GOLD), _f([[2, 5], [18, 5], [18, 8], [2, 8]], Color(0.7, 0.75, 0.85))]
		"fit_all": layers = [_l([[2, 7], [2, 2], [7, 2]]), _l([[13, 2], [18, 2], [18, 7]]), _l([[18, 13], [18, 18], [13, 18]]), _l([[7, 18], [2, 18], [2, 13]]), _c(Vector2(7, 8), 1.6, BLUE), _c(Vector2(13, 12), 1.6, GOLD), _c(Vector2(10, 7), 1.2)]
		"duplicate": layers = [_l([[2, 6], [2, 18], [14, 18]], 1.6), _f([[6, 2], [18, 2], [18, 14], [6, 14]], BLUE)]
		"rename": layers = [_f([[3, 14], [13, 4], [16, 7], [6, 17], [2, 18]], GOLD), _l([[2, 19], [18, 19]], 1.4)]
		"key": layers = [_f([[10, 2], [18, 10], [10, 18], [2, 10]], GOLD)]
		"keypose": layers = [_f([[6, 4], [11, 9], [6, 14], [1, 9]], GOLD), _f([[14, 6], [19, 11], [14, 16], [9, 11]], GOLD)]
		"keydel": layers = [_f([[8, 2], [15, 9], [8, 16], [1, 9]], GOLD), _l([[11, 12], [19, 19]], 2.4, RED), _l([[19, 12], [11, 19]], 2.4, RED)]
		"prevkey": layers = [_f([[16, 4], [9, 10], [16, 16]]), _f([[6, 6], [10, 10], [6, 14], [2, 10]], GOLD)]
		"nextkey": layers = [_f([[4, 4], [11, 10], [4, 16]]), _f([[14, 6], [18, 10], [14, 14], [10, 10]], GOLD)]
		"docs": layers = [_f([[2, 4], [9, 3], [10, 5], [10, 17], [9, 15], [2, 16]], BLUE), _f([[18, 4], [11, 3], [10, 5], [10, 17], [11, 15], [18, 16]], W),
			_l([[12, 7], [16, 7]], 1.0, Color(0.2, 0.25, 0.35)), _l([[12, 10], [16, 10]], 1.0, Color(0.2, 0.25, 0.35))]
		"help": layers = [_ring(Vector2(10, 10), 8.0, 1.8, BLUE), _l([[7, 7], [8, 4.5], [12, 4.5], [13, 7], [10, 10], [10, 12]], 1.8), _c(Vector2(10, 15), 1.3)]
		# Versions, the mesh editor, mods (and the drawing tools the mesh editor shares).
		"patch": layers = [_f([[3, 2], [13, 2], [17, 6], [17, 18], [3, 18]], BLUE), _l([[6, 7], [12, 7]], 1.4, Color(0.1, 0.12, 0.18)), _l([[6, 10], [14, 10]], 1.4, Color(0.1, 0.12, 0.18)), _l([[6, 13], [11, 13]], 1.4, Color(0.1, 0.12, 0.18)), _c(Vector2(14.5, 15), 3.6, GOLD), _l([[13, 15], [14.3, 16.3], [16.3, 13.6]], 1.3, Color(0.1, 0.12, 0.18))]
		"mesh": layers = [_f([[10, 2], [18, 6], [10, 10], [2, 6]], GOLD), _f([[2, 6], [10, 10], [10, 18], [2, 14]], BLUE), _f([[18, 6], [10, 10], [10, 18], [18, 14]], Color(0.75, 0.42, 0.14)), _l([[2, 6], [10, 10], [18, 6]], 1.0, Color(0.1, 0.12, 0.18)), _l([[10, 10], [10, 18]], 1.0, Color(0.1, 0.12, 0.18))]
		"mod": layers = [_f([[2, 6], [7, 6], [7, 3], [11, 3], [11, 6], [16, 6], [16, 10], [19, 10], [19, 14], [16, 14], [16, 18], [2, 18]], BLUE), _c(Vector2(9, 12), 3.0, GOLD), _c(Vector2(9, 12), 1.2, Color(0.1, 0.12, 0.18))]
		"select": layers = [_f([[4, 2], [16, 12], [11, 12.5], [14, 18], [11.5, 19], [8.5, 13.5], [4, 17]])]
		"node": layers = [_l([[3, 16], [8, 5], [17, 9]], 1.4, BLUE), _f([[1, 14], [5, 14], [5, 18], [1, 18]]), _f([[6, 3], [10, 3], [10, 7], [6, 7]], GOLD), _f([[15, 7], [19, 7], [19, 11], [15, 11]])]
		"rect": layers = [_f([[3, 5], [17, 5], [17, 15], [3, 15]], BLUE), _l([[3, 5], [17, 5], [17, 15], [3, 15], [3, 5]], 1.4)]
		"ellipse": layers = [{"pts": Icons.arc(Vector2(10, 10), 7.5, 0, TAU, 24), "fill": BLUE}, _ring(Vector2(10, 10), 7.5, 1.4)]
		"star_tool": layers = [_f([[10, 1.5], [12.4, 7.5], [18.5, 7.8], [13.7, 11.8], [15.3, 18], [10, 14.5], [4.7, 18], [6.3, 11.8], [1.5, 7.8], [7.6, 7.5]], GOLD)]
		"pen": layers = [_l([[2, 18], [7, 6], [18, 4]], 1.4, BLUE), _f([[12, 2], [17, 7], [9, 15], [5, 15], [5, 11]], W), _c(Vector2(9, 11), 1.3, Color(0.1, 0.12, 0.18))]
		"pencil": layers = [_f([[3, 14], [13, 4], [16, 7], [6, 17], [2, 18]], GOLD), _f([[13, 4], [15, 2], [18, 5], [16, 7]], RED), _l([[2, 18], [4, 16]], 1.4, Color(0.1, 0.12, 0.18))]
		"text": layers = [_f([[3, 3], [17, 3], [17, 7], [15, 7], [14, 5], [11.5, 5], [11.5, 16], [13.5, 17], [6.5, 17], [8.5, 16], [8.5, 5], [6, 5], [5, 7], [3, 7]])]
		"picker": layers = [_f([[12, 4], [16, 8], [7, 17], [3, 18], [4, 14]], W), _f([[13, 2], [18, 7], [16, 9], [11, 4]], BLUE), _f([[4, 14], [7, 17], [3, 18]], GOLD)]
		"export": layers = [_f([[3, 3], [17, 3], [17, 17], [3, 17]], BLUE), _f([[3, 12], [8, 7], [12, 11], [14, 9], [17, 12], [17, 17], [3, 17]], GREEN), _c(Vector2(13, 6.5), 1.6, GOLD)]
		"open": layers = [_f([[2, 4], [8, 4], [10, 6], [17, 6], [17, 16], [2, 16]], GOLD), _f([[4, 9], [19, 9], [17, 16], [2, 16]], Color(1.0, 0.88, 0.5))]
		"new": layers = [_f([[4, 2], [12, 2], [16, 6], [16, 18], [4, 18]], W), _f([[12, 2], [16, 6], [12, 6]], BLUE), _f([[8.5, 9], [11.5, 9], [11.5, 11], [13.5, 11], [13.5, 14], [11.5, 14], [11.5, 16], [8.5, 16], [8.5, 14], [6.5, 14], [6.5, 11], [8.5, 11]], GREEN)]
		"grid": layers = [_l([[2, 7], [18, 7]], 1.2, BLUE), _l([[2, 13], [18, 13]], 1.2, BLUE), _l([[7, 2], [7, 18]], 1.2, BLUE), _l([[13, 2], [13, 18]], 1.2, BLUE)]
		"eye": layers = [{"pts": Icons.arc(Vector2(10, 16), 10.0, PI * 1.2, PI * 1.8, 12) + Icons.arc(Vector2(10, 4), 10.0, PI * 0.2, PI * 0.8, 12), "fill": W},
			_c(Vector2(10, 10), 3.4, Color(0.15, 0.35, 0.6)), _c(Vector2(10, 10), 1.6, Color(0.05, 0.06, 0.1))]
		"eye_off": layers = [{"pts": Icons.arc(Vector2(10, 16), 10.0, PI * 1.2, PI * 1.8, 12) + Icons.arc(Vector2(10, 4), 10.0, PI * 0.2, PI * 0.8, 12), "fill": Color(0.45, 0.48, 0.55)},
			_l([[3, 17], [17, 3]], 2.2, RED)]
		"lock": layers = [{"pts": Icons.arc(Vector2(10, 8), 4.5, PI, TAU, 10), "stroke": GOLD, "width": 2.0, "closed": false}, _l([[5.5, 8], [5.5, 10]], 2.0, GOLD), _l([[14.5, 8], [14.5, 10]], 2.0, GOLD),
			_f([[3.5, 10], [16.5, 10], [16.5, 18], [3.5, 18]], GOLD), _c(Vector2(10, 13.5), 1.4, Color(0.2, 0.15, 0.05))]
		"unlock": layers = [{"pts": Icons.arc(Vector2(14, 6), 4.5, PI, TAU, 10), "stroke": Color(0.45, 0.48, 0.55), "width": 2.0, "closed": false}, _l([[18.5, 6], [18.5, 9]], 2.0, Color(0.45, 0.48, 0.55)),
			_f([[2.5, 10], [15.5, 10], [15.5, 18], [2.5, 18]], Color(0.45, 0.48, 0.55))]
		"snap": layers = [_l([[3, 7], [17, 7]], 1.0, BLUE), _l([[7, 3], [7, 17]], 1.0, BLUE), _l([[3, 13], [17, 13]], 1.0, BLUE), _l([[13, 3], [13, 17]], 1.0, BLUE), _ring(Vector2(13, 13), 3.0, 1.8, GOLD)]
		_: return []
	return layers


## Every icon button, everywhere (Talos and the game alike): its icon and a
## short label beside it - one or two words (`label`, or short_label() of the
## tooltip's title) - with the full name, keys and help in its tooltip.
static func dress(b: Button, icon: String, tooltip: String, label := "") -> Button:
	var t := get_icon(icon)
	if t:
		b.icon = t
		b.expand_icon = false
		b.text = label if label != "" else short_label(tooltip)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT if b.text != "" else HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(maxf(b.custom_minimum_size.x, 44), maxf(b.custom_minimum_size.y, 38))
		IconAnim.attach(b, icon)   # (alive while hovered)
	b.tooltip_text = tooltip
	return b


## Short labels for the long titles (the rest: the title itself if short,
## else its first two words).
const SHORT := {
	"Save to file": "Save", "Reload from file": "Reload", "Preview dialogue": "Preview",
	"Reload sprites": "Reload art", "Documentation": "Help", "Pilot's guide": "Guide",
	"Exit Talos": "Exit", "Exit the level editor": "Exit", "Exit preview": "Exit",
	"Close the Automaton": "Close", "Close the map": "Close", "Close the Field Computer": "Close",
	"Asset browser": "Browser", "Centre on your ship": "My ship", "Trade routes": "Routes",
	"Whole sector": "Whole map", "Save layout": "Save", "Load saved game": "Load",
	"Main menu": "Menu", "Pump from the hold": "Pump", "Accept mission": "Accept",
	"Test in game": "Test", "Import the main quest": "Import", "Zoom to page": "Fit page",
	"Snap to grid": "Snap", "Export PNG": "Export", "Reload patches": "Reload",
	"Open this patch": "Open patch", "Previous step": "Previous", "Next step": "Next",
	"Play the sound": "Play", "New scenario": "New", "Revert to generated": "Revert",
	"Add citizen line": "Add line", "Apply paint": "Apply",
	"Saved presets": "Presets", "Factory paint": "Factory", "Rename step": "Rename",
	"Sell all cargo": "Sell all", "Clear route": "Clear", "Brush size": "Brush",
	"Where and when it's used": "Where used", "Duplicate": "Copy", "Save as": "Save as",
	"Select and transform": "Select", "Star and polygon": "Star", "Pencil (freehand)": "Pencil",
	"Pen (Bezier)": "Pen",
}
## Titles made at run time ("Land on Amnissos"): their opening words' short form.
const SHORT_PREFIX := {"Land on ": "Land", "Plot route to ": "Plot route", "Buy the ": "Buy",
	"Enter: ": "Enter", "Skin: ": "Skin", "Take out ": "Take out", "Sell all ": "Sell all"}
const FILLER := ["and", "the", "to", "of", "a", "on", "in", "for", "with", "from", "your"]


## A button's label from its tooltip ("Title      [keys]\nhelp").
static func short_label(tooltip: String) -> String:
	var title := tooltip.get_slice("\n", 0)
	var k := title.find("      [")
	if k >= 0:
		title = title.left(k)
	title = title.strip_edges()
	if SHORT.has(title):
		return SHORT[title]
	for pre in SHORT_PREFIX:
		if title.begins_with(pre):
			return SHORT_PREFIX[pre]
	if title.length() <= 14:
		return title
	# The first two words - never ending on "and", "the", "to"...
	var words := Array(title.split(" ", false)).slice(0, 2)
	while words.size() > 1 and str(words[-1]).to_lower() in FILLER:
		words.pop_back()
	return " ".join(words)


## An in-game action button: its icon plus a short number (a price, an
## amount, a rating) - the words go in the tooltip.
static func action(b: Button, icon: String, value: String, tooltip: String) -> Button:
	dress(b, icon, tooltip)
	if value != "":   # (the verb, then the number: "Buy 1,200"; a value in words - "Buy 5" - as it is)
		var verb := short_label(tooltip).get_slice(" ", 0)
		var worded := value.unicode_at(0) > 64 and value.left(1).to_upper() != value.left(1).to_lower()
		b.text = (verb + " " + value) if verb != "" and not verb.contains("%") and not worded else value
		b.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size.x = maxf(b.custom_minimum_size.x, 70)
	return b


## Same, but keeps the text (for tabs).
static func dress_tab(b: Button, icon: String, tooltip: String) -> Button:
	var t := get_icon(icon)
	if t:
		b.icon = t
		b.expand_icon = false
	b.tooltip_text = tooltip
	return b


## A documentation button (opens EditorDocs at a section).
static func docs_button(owner: Node, section: String, file := EditorDocs.FILE) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): EditorDocs.open(owner, section, file))
	if file == EditorDocs.GAME:
		return dress(b, "docs", tip("Pilot's guide", "F1", "Opens the pilot's guide at this screen's chapter: everything about flying, fighting, trading,\nstations, planets and the galaxy, with links between pages, back / forward and a search box. Esc or ✕ closes it."))
	return dress(b, "docs", tip("Documentation", "F1", "Opens the editor documentation at this screen's section: every tool and option explained,\nwith links between sections and a search box. Esc or ✕ closes it."))


# --- The mesh editor's menu (its right-click icons) ------------------------------------

const MESH_ICONS := ["m_move", "m_rotate", "m_scale", "m_extrude", "m_subdivide", "m_merge", "m_flip", "m_normals",
	"m_box", "m_cylinder", "m_cone", "m_sphere", "m_plane", "m_torus", "m_mirror_x", "m_mirror_y", "m_mirror_z",
	"m_mirror_apply", "m_sym_x", "m_sym_y", "m_sym_z", "m_symmetrize", "m_symmetrize_back", "m_prop", "m_falloff",
	"m_connected", "m_vertex", "m_edge", "m_face", "m_object", "m_edit", "m_frame", "m_frame_all", "m_front",
	"m_side", "m_top", "m_ortho", "m_sel_all", "m_sel_none", "m_sel_invert", "m_icons", "m_list", "m_tpose", "m_weapons", "m_gizmo", "m_panel_left", "m_panel_right", "m_maximize", "m_restore", "m_move_smart", "m_move_persp", "m_sel_material", "m_spherize", "m_curve", "m_flatten", "m_ref_image", "m_revert",
	"m_union", "m_difference", "m_intersect", "m_slice", "m_shapes", "m_shape_save", "m_shape_add",
	"m_knife", "m_ngons", "m_auto_select", "m_dissolve", "m_symmetrize_topo", "m_bind_auto", "m_bind_bone", "m_bone_parts",
	"m_materials", "m_mat_new", "m_mat_duplicate", "m_mat_rename", "m_mat_delete", "m_mat_assign",
	"m_duplicate_mesh", "m_merge_dist", "m_auto_merge", "m_inset", "m_fillet", "m_loop_cut", "m_sel_loop", "m_sel_ring"]
const AX := [Color(1.0, 0.38, 0.35), Color(0.45, 0.95, 0.45), Color(0.4, 0.65, 1.0)]   # (X red, Y green, Z blue)
const INK := Color(0.1, 0.12, 0.18)


## A shaded ball (a material's look): its colour, a darker side and a highlight.
static func _ball(c: Vector2, r: float, col: Color) -> Array:
	return [_c(c, r, col.darkened(0.35)), _c(c + Vector2(-r, -r) * 0.18, r * 0.78, col), _c(c + Vector2(-r, -r) * 0.4, r * 0.28, Color(1, 1, 1, 0.8))]


## A cube in outline (its three visible faces), for the mode and view icons.
static func _cube(face := -1, col := BLUE) -> Array:
	var top := [[10, 2], [17, 5.5], [10, 9], [3, 5.5]]
	var left := [[3, 5.5], [10, 9], [10, 18], [3, 14.5]]
	var right := [[17, 5.5], [10, 9], [10, 18], [17, 14.5]]
	var out := []
	for i in 3:
		var f: Array = [top, left, right][i]
		out.append(_f(f, GOLD if i == face else Color(col, 0.35 if face >= 0 else 0.55)))
	out.append(_l([[3, 5.5], [10, 2], [17, 5.5], [17, 14.5], [10, 18], [3, 14.5], [3, 5.5]], 1.3, W))
	out.append(_l([[3, 5.5], [10, 9], [17, 5.5]], 1.0, W))
	out.append(_l([[10, 9], [10, 18]], 1.0, W))
	return out


static func _arrow(a: Vector2, b: Vector2, col := W, w := 1.6) -> Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	return [_l([[a.x, a.y], [b.x, b.y]], w, col), _f([[b.x + d.x, b.y + d.y], [b.x - d.x * 3 + n.x * 2.6, b.y - d.y * 3 + n.y * 2.6],
		[b.x - d.x * 3 - n.x * 2.6, b.y - d.y * 3 - n.y * 2.6]], col)]


## Two discs (the boolean icons: A on the left, B on the right) as polygons.
static func _venn() -> Array:
	return [Icons.arc(Vector2(7.5, 10), 6.0, 0, TAU, 28), Icons.arc(Vector2(12.5, 10), 6.0, 0, TAU, 28)]


static func _poly_fill(pts: PackedVector2Array, col: Color) -> Dictionary:
	return {"pts": pts, "fill": col}


static func _poly_line(pts: PackedVector2Array, col: Color, w := 1.2) -> Dictionary:
	return {"pts": pts, "stroke": col, "width": w, "fill": Color(0, 0, 0, 0)}


## A little library of shapes: a cube, a ball, a cone, a ring in a 2 x 2 grid.
static func _shapes_grid(scale := 1.0) -> Array:
	var s := scale
	return [_f([[2 * s, 4 * s], [5 * s, 2.5 * s], [8 * s, 4 * s], [8 * s, 8 * s], [5 * s, 9.5 * s], [2 * s, 8 * s]], BLUE),
		_l([[2 * s, 4 * s], [5 * s, 5.5 * s], [8 * s, 4 * s]], 1.0, W), _l([[5 * s, 5.5 * s], [5 * s, 9.5 * s]], 1.0, W),
		_c(Vector2(15 * s, 5.5 * s), 3.6 * s, GOLD), _c(Vector2(13.8 * s, 4.4 * s), 1.0 * s, Color(W, 0.8)),
		_f([[5 * s, 11 * s], [8.5 * s, 18 * s], [1.5 * s, 18 * s]], Color(BLUE, 0.85)),
		_ring(Vector2(15 * s, 14.5 * s), 3.0 * s, 1.8 * s, GOLD)]


static func _mesh_icon(name: String) -> Array:
	match name:
		"m_union":
			var v := _venn()
			var u := Geometry2D.merge_polygons(v[0], v[1])
			return [_poly_fill(u[0], BLUE), _poly_line(u[0], W, 1.4)]
		"m_difference":
			var v := _venn()
			var d := Geometry2D.clip_polygons(v[0], v[1])
			return [_poly_line(v[1], Color(W, 0.45), 1.0), _poly_fill(d[0], BLUE), _poly_line(d[0], W, 1.3)]
		"m_intersect":
			var v := _venn()
			var i := Geometry2D.intersect_polygons(v[0], v[1])
			return [_poly_line(v[0], Color(W, 0.45), 1.0), _poly_line(v[1], Color(W, 0.45), 1.0), _poly_fill(i[0], GOLD), _poly_line(i[0], W, 1.2)]
		"m_slice":
			var left := Icons.arc(Vector2(8.5, 10), 6.5, PI * 0.5, PI * 1.5, 16)
			var right := Icons.arc(Vector2(11.5, 10), 6.5, -PI * 0.5, PI * 0.5, 16)
			return [_poly_fill(left, BLUE), _poly_fill(right, Color(BLUE, 0.55)), _poly_line(left, W, 1.1), _poly_line(right, W, 1.1),
				_l([[10, 1], [10, 19]], 1.6, GOLD)]
		"m_shapes":
			return _shapes_grid()
		"m_shape_save":
			return _shapes_grid(0.8) + [_c(Vector2(15.5, 15.5), 4.2, GOLD), _l([[15.5, 13], [15.5, 18]], 1.6, INK), _l([[13, 15.5], [18, 15.5]], 1.6, INK)]
		"m_shape_add":
			return _shapes_grid(0.8) + _arrow(Vector2(17, 9), Vector2(17, 18), GOLD, 1.8)
		"m_panel_left", "m_panel_right":   # a window, one side of it a panel
			var left := name == "m_panel_left"
			var strip := [[2.5, 3.5], [7, 3.5], [7, 16.5], [2.5, 16.5]] if left else [[13, 3.5], [17.5, 3.5], [17.5, 16.5], [13, 16.5]]
			return [_f([[2, 3], [18, 3], [18, 17], [2, 17]], Color(BLUE, 0.25)), _f(strip, GOLD), _l([[2, 3], [18, 3], [18, 17], [2, 17], [2, 3]], 1.3, W)]
		"m_maximize":   # four corners pushed out
			return [_l([[2, 7], [2, 2], [7, 2]], 1.8, W), _l([[13, 2], [18, 2], [18, 7]], 1.8, W), _l([[18, 13], [18, 18], [13, 18]], 1.8, W), _l([[7, 18], [2, 18], [2, 13]], 1.8, W),
				_f([[6, 6], [14, 6], [14, 14], [6, 14]], Color(BLUE, 0.5))]
		"m_restore":   # four corners pulled in
			return [_l([[2, 7], [7, 7], [7, 2]], 1.8, W), _l([[13, 2], [13, 7], [18, 7]], 1.8, W), _l([[18, 13], [13, 13], [13, 18]], 1.8, W), _l([[7, 18], [7, 13], [2, 13]], 1.8, W),
				_f([[9, 9], [11, 9], [11, 11], [9, 11]], GOLD)]
		"m_move_smart":   # a face, its normal and an arrow along its surface
			return [_f([[3, 13], [11, 10], [17, 13], [9, 16]], Color(BLUE, 0.6)), _l([[3, 13], [11, 10], [17, 13], [9, 16], [3, 13]], 1.0, W)] \
				+ _arrow(Vector2(10, 13), Vector2(10, 3), AX[2], 1.6) + _arrow(Vector2(10, 13), Vector2(17, 7.5), AX[0], 1.4)
		"m_move_persp":   # a ground grid in perspective, an arrow across it
			return [_l([[1, 18], [6, 9], [14, 9], [19, 18], [1, 18]], 1.2, Color(W, 0.8)), _l([[7.5, 18], [8.7, 9]], 0.9, Color(W, 0.5)),
				_l([[12.5, 18], [11.3, 9]], 0.9, Color(W, 0.5)), _l([[3.5, 13.5], [16.5, 13.5]], 0.9, Color(W, 0.5))] \
				+ _arrow(Vector2(6, 15.5), Vector2(15, 11.5), GOLD, 1.7) + [_c(Vector2(6, 15.5), 1.6, GOLD)]
		"m_sel_material":   # two patches of faces, one coloured: the island picked by its material
			return [_f([[2, 4], [9, 4], [9, 10], [2, 10]], GOLD), _f([[10, 4], [18, 4], [18, 10], [10, 10]], GOLD),
				_f([[2, 11], [9, 11], [9, 17], [2, 17]], GOLD), _f([[10, 11], [18, 11], [18, 17], [10, 17]], Color(BLUE, 0.35)),
				_l([[9.5, 3], [9.5, 18]], 1.0, INK), _l([[1.5, 10.5], [18.5, 10.5]], 1.0, INK)]
		"m_spherize":   # a square's corners pulled out onto a circle
			return [_l([[4, 4], [16, 4], [16, 16], [4, 16], [4, 4]], 1.0, Color(W, 0.45)), _ring(Vector2(10, 10), 7.5, 1.6, GOLD)] \
				+ _arrow(Vector2(10, 10), Vector2(15.3, 4.7), BLUE, 1.2) + [_c(Vector2(10, 10), 1.5, W)]
		"m_curve":   # a row of points bent along a curve, its end handles out
			var cp := [Vector2(2.5, 15), Vector2(6, 3), Vector2(14, 3), Vector2(17.5, 15)]
			var pts := []
			for i in 13:
				var t := i / 12.0
				var u := 1.0 - t
				var q: Vector2 = cp[0] * (u * u * u) + cp[1] * (3.0 * u * u * t) + cp[2] * (3.0 * u * t * t) + cp[3] * (t * t * t)
				pts.append([q.x, q.y])
			var out := [_l([[2.5, 15], [17.5, 15]], 1.0, Color(W, 0.35)), _l([[2.5, 15], [6, 3]], 1.0, Color(W, 0.7)), _l([[17.5, 15], [14, 3]], 1.0, Color(W, 0.7)),
				_l(pts, 1.7, GOLD), _c(Vector2(6, 3), 1.6, W), _c(Vector2(14, 3), 1.6, W)]
			for e in [Vector2(2.5, 15), Vector2(17.5, 15)]:
				out.append(_f([[e.x - 1.8, e.y - 1.8], [e.x + 1.8, e.y - 1.8], [e.x + 1.8, e.y + 1.8], [e.x - 1.8, e.y + 1.8]], BLUE))
			return out
		"m_flatten":   # bumpy points pressed down onto a flat plane
			return [_f([[1.5, 13], [12, 13], [18.5, 17], [8, 17]], Color(BLUE, 0.45)), _l([[1.5, 13], [12, 13], [18.5, 17], [8, 17], [1.5, 13]], 1.1, W),
				_c(Vector2(5, 7), 1.5, GOLD), _c(Vector2(10, 4.5), 1.5, GOLD), _c(Vector2(15, 8), 1.5, GOLD)] \
				+ _arrow(Vector2(10, 6.5), Vector2(10, 14.5), W, 1.3)
		"m_ref_image":   # a picture (a mountain, a sun) behind a cube's outline
			return [_f([[2, 3], [15, 3], [15, 13], [2, 13]], Color(BLUE, 0.35)), _l([[2, 3], [15, 3], [15, 13], [2, 13], [2, 3]], 1.1, W),
				_f([[2.5, 12.5], [7, 6.5], [10, 10], [12, 8], [14.5, 12.5]], Color(GOLD, 0.8)), _c(Vector2(11.5, 5.5), 1.4, GOLD),
				_l([[9, 10], [18, 10], [18, 18], [9, 18], [9, 10]], 1.5, W)]
		"m_revert":   # a page, an arrow curling back to it
			var arc := Icons.arc(Vector2(11, 11), 5.5, PI * 1.1, PI * 2.4, 16)
			var pts := []
			for q in arc:
				pts.append([q.x, q.y])
			var e: Vector2 = arc[0]
			return [_f([[7, 3], [17, 3], [17, 18], [7, 18]], Color(BLUE, 0.4)), _l(pts, 1.8, GOLD), _f([[e.x - 3.5, e.y - 1], [e.x + 1, e.y - 3], [e.x + 0.5, e.y + 2]], GOLD)]
		"m_gizmo":   # the move / turn / scale handles: a ring, three arrows
			return [_ring(Vector2(10, 10), 7.5, 1.3, Color(W, 0.7))] + _arrow(Vector2(10, 10), Vector2(18, 10), AX[0], 1.5) \
				+ _arrow(Vector2(10, 10), Vector2(10, 2), AX[1], 1.5) + _arrow(Vector2(10, 10), Vector2(4, 16), AX[2], 1.5) + [_c(Vector2(10, 10), 1.6, W)]
		"m_tpose":   # a figure, its arms straight out
			return [_c(Vector2(10, 3.5), 2.4, GOLD), _l([[2, 7.5], [18, 7.5]], 2.0, W), _l([[10, 6], [10, 12.5]], 2.2, BLUE),
				_l([[10, 12.5], [7, 18.5]], 2.0, BLUE), _l([[10, 12.5], [13, 18.5]], 2.0, BLUE)]
		"m_weapons":  # a rifle
			return [_f([[2, 9], [13, 9], [13, 11], [2, 11]], BLUE), _f([[13, 8.5], [18, 8.5], [18, 10], [13, 10]], W), _f([[4, 11], [7, 11], [6, 16], [3, 16]], BLUE),
				_f([[8, 11], [10, 11], [10, 14], [8, 14]], GOLD), _l([[6, 7], [11, 7]], 1.4, GOLD)]
		"m_icons":
			var out := []
			for i in 4:
				var o := Vector2(2 + (i % 2) * 9, 2 + (i / 2) * 9)
				out.append(_f([[o.x, o.y], [o.x + 7, o.y], [o.x + 7, o.y + 7], [o.x, o.y + 7]], BLUE if i != 0 else GOLD))
			return out
		"m_list":
			var out := []
			for i in 4:
				var y := 3.5 + i * 4.3
				out.append(_f([[2, y - 1.4], [5, y - 1.4], [5, y + 1.4], [2, y + 1.4]], GOLD if i == 0 else BLUE))
				out.append(_l([[7, y], [18, y]], 1.4, W))
			return out
		"m_move":
			return _arrow(Vector2(10, 10), Vector2(10, 2)) + _arrow(Vector2(10, 10), Vector2(10, 18)) + _arrow(Vector2(10, 10), Vector2(2, 10)) \
				+ _arrow(Vector2(10, 10), Vector2(18, 10)) + [_c(Vector2(10, 10), 2.2, GOLD)]
		"m_rotate":
			var pts := Icons.arc(Vector2(10, 10), 6.5, 0.4, TAU - 0.6, 24)
			var arr := []
			for q in pts:
				arr.append([q.x, q.y])
			var e: Vector2 = pts[pts.size() - 1]
			return [_l(arr, 1.8, BLUE), _f([[e.x + 3.2, e.y - 1.2], [e.x - 0.6, e.y + 3.4], [e.x - 1.6, e.y - 2.6]], W), _c(Vector2(10, 10), 1.8, GOLD)]
		"m_scale":
			return [_l([[2, 8], [2, 18], [12, 18], [12, 8], [2, 8]], 1.3, Color(W, 0.6)), _l([[2, 2], [18, 2], [18, 18]], 1.4, BLUE)] \
				+ _arrow(Vector2(6, 14), Vector2(16, 4), GOLD)
		"m_extrude":
			return [_f([[2, 14], [10, 11], [18, 14], [10, 17]], BLUE), _l([[2, 14], [10, 11], [18, 14], [10, 17], [2, 14]], 1.0, W)] + _arrow(Vector2(10, 13), Vector2(10, 2), GOLD, 1.8)
		"m_knife":   # a blade cutting a face in two along a dashed line
			return [_f([[2, 13], [10, 9], [18, 13], [10, 17]], Color(BLUE, 0.45)), _l([[2, 13], [10, 9], [18, 13], [10, 17], [2, 13]], 1.0, W),
				_l([[6, 11], [8, 12]], 1.3, GOLD), _l([[10, 13], [12, 14]], 1.3, GOLD), _l([[14, 15], [15, 15.5]], 1.3, GOLD),
				_f([[5, 9.5], [15.5, 1.5], [17.5, 3.5], [7.5, 11]], W), _f([[15.5, 1.5], [18.5, 0.8], [17.5, 3.5]], Color(W, 0.8)),
				_f([[2.5, 11.5], [5, 9.5], [6.2, 10.8], [3.8, 12.8]], GOLD)]
		"m_auto_select":   # a point, an edge and a face - and the pointer that picks among them
			return [_f([[2, 12], [9, 12], [9, 18], [2, 18]], Color(BLUE, 0.6)), _l([[2, 3], [12, 3]], 1.6, W), _c(Vector2(16, 3), 2.0, W),
				_f([[11, 7], [18.5, 14], [15, 14.2], [16.8, 18.5], [15, 19.2], [13.3, 15], [11, 17.2]], GOLD)]
		"m_symmetrize_topo":   # a half shape with its faces, the mirror line, its copied outline
			return [_f([[10, 3], [3, 6], [2, 12], [5, 17], [10, 17]], Color(BLUE, 0.6)), _l([[10, 3], [3, 6], [2, 12], [5, 17], [10, 17]], 1.3, W),
				_l([[3, 6], [10, 10]], 1.0, Color(W, 0.7)), _l([[2, 12], [10, 10]], 1.0, Color(W, 0.7)),
				_l([[10, 3], [17, 6], [18, 12], [15, 17], [10, 17]], 1.2, Color(GOLD, 0.9)), _l([[17, 6], [10, 10]], 0.9, Color(GOLD, 0.6)),
				_l([[18, 12], [10, 10]], 0.9, Color(GOLD, 0.6)), _l([[10, 1], [10, 19]], 1.5, AX[0])]
		"m_bind_auto", "m_bind_bone":   # a bone (two knuckles and a shaft) and a box tied to it
			var out := [_l([[3, 17], [12, 8]], 2.2, W), _c(Vector2(3, 17), 2.0, W), _c(Vector2(12, 8), 2.0, W),
				_f([[12, 2], [18, 2], [18, 8], [12, 8]], Color(BLUE, 0.7)), _l([[12, 2], [18, 2], [18, 8], [12, 8], [12, 2]], 1.0, W)]
			if name == "m_bind_auto":   # (to the bones nearest: three threads)
				out += [_l([[15, 8], [9, 12]], 1.0, GOLD), _l([[16, 8], [7, 15]], 1.0, GOLD), _l([[17, 8], [14, 15]], 1.0, GOLD)]
			else:   # (to the one bone: one firm tie)
				out += [_l([[13, 9], [8, 12]], 1.8, GOLD), _c(Vector2(8, 12), 1.4, GOLD)]
			return out
		"m_bone_parts":   # a bone (two knuckles and a shaft) and the rounded part grown along it
			return [_f([[5.5, 18.5], [1.5, 14.5], [12.5, 3.5], [16.5, 1.5], [18.5, 3.5], [16.5, 7.5]], Color(BLUE, 0.6)),
				_l([[5.5, 18.5], [1.5, 14.5], [12.5, 3.5], [16.5, 1.5], [18.5, 3.5], [16.5, 7.5], [5.5, 18.5]], 1.0, W),
				_l([[4, 16], [15, 5]], 2.0, GOLD), _c(Vector2(4, 16), 1.8, GOLD), _c(Vector2(15, 5), 1.8, GOLD)]
		"m_duplicate_mesh":   # a face, and its copy lifted off it on an arrow
			return [_l([[2, 12], [9, 9], [16, 12], [9, 15], [2, 12]], 1.1, Color(W, 0.5)),
				_f([[4, 7], [11, 4], [18, 7], [11, 10]], Color(BLUE, 0.7)), _l([[4, 7], [11, 4], [18, 7], [11, 10], [4, 7]], 1.2, W)] \
				+ _arrow(Vector2(5, 17), Vector2(12, 13.5), GOLD, 1.4)
		"m_merge_dist":   # two points within a span (its ends marked) made one
			return [_l([[3, 15], [17, 15]], 1.0, Color(W, 0.6)), _l([[3, 13], [3, 17]], 1.0, Color(W, 0.6)), _l([[17, 13], [17, 17]], 1.0, Color(W, 0.6)),
				_c(Vector2(7, 7), 2.4, BLUE), _c(Vector2(13, 7), 2.4, BLUE)] + _arrow(Vector2(4, 7), Vector2(8.5, 7), W, 1.0) \
				+ _arrow(Vector2(16, 7), Vector2(11.5, 7), W, 1.0) + [_c(Vector2(10, 7), 1.8, GOLD)]
		"m_auto_merge":   # a moved point landing on another, which takes it in (a ring round it)
			return [_ring(Vector2(13, 13), 4.5, 1.2, Color(GOLD, 0.8)), _c(Vector2(13, 13), 2.2, GOLD), _l([[13, 13], [18, 8]], 1.0, Color(W, 0.6)),
				_l([[13, 13], [8, 18]], 1.0, Color(W, 0.6)), _c(Vector2(3.5, 3.5), 1.8, Color(BLUE, 0.8))] + _arrow(Vector2(4.5, 4.5), Vector2(9.5, 9.5), W, 1.3)
		"m_inset":   # a face, a smaller one inside it joined at the corners
			return [_l([[2, 2], [18, 2], [18, 18], [2, 18], [2, 2]], 1.4, W), _f([[6, 6], [14, 6], [14, 14], [6, 14]], Color(BLUE, 0.7)),
				_l([[6, 6], [14, 6], [14, 14], [6, 14], [6, 6]], 1.3, GOLD), _l([[2, 2], [6, 6]], 1.0, Color(W, 0.7)), _l([[18, 2], [14, 6]], 1.0, Color(W, 0.7)),
				_l([[18, 18], [14, 14]], 1.0, Color(W, 0.7)), _l([[2, 18], [6, 14]], 1.0, Color(W, 0.7))]
		"m_fillet":   # a block's corner rounded off: the arc (its strip's rows marked), the old sharp corner faint
			var arc := []
			for i in 7:
				var a := -PI * 0.5 + i * PI / 12.0
				arc.append([10.0 + 8.0 * cos(a), 11.0 + 8.0 * sin(a)])
			var out := [_f([[2, 18], [2, 3]] + arc + [[18, 18]], Color(BLUE, 0.45)), _l([[10, 3], [18, 3], [18, 11]], 1.0, Color(W, 0.4)),
				_l([[2, 18], [2, 3], [10, 3]], 1.3, W), _l([[18, 11], [18, 18], [2, 18]], 1.3, W)]
			for i in range(1, 6):
				var q: Array = arc[i]
				out.append(_l([q, [q[0] - (q[0] - 10.0) * 0.4, q[1] - (q[1] - 11.0) * 0.4]], 1.0, Color(W, 0.7)))
			out.append(_l(arc, 2.0, GOLD))
			return out
		"m_loop_cut":   # a band of quads, a new loop cut round it (marked where it crosses)
			return [_f([[2, 5], [18, 5], [18, 15], [2, 15]], Color(BLUE, 0.45)), _l([[2, 5], [18, 5]], 1.2, W), _l([[2, 15], [18, 15]], 1.2, W),
				_l([[2, 5], [2, 15]], 1.0, Color(W, 0.7)), _l([[18, 5], [18, 15]], 1.0, Color(W, 0.7)), _l([[10, 2], [10, 18]], 1.8, GOLD),
				_f([[10, 3], [12, 5], [10, 7], [8, 5]], GOLD), _f([[10, 13], [12, 15], [10, 17], [8, 15]], GOLD)]
		"m_sel_loop", "m_sel_ring":   # a grid of quads: a loop along it picked, or the ring of edges across it
			var out := [_f([[2, 2], [18, 2], [18, 18], [2, 18]], Color(BLUE, 0.35))]
			for i in 3:
				var v := 2.0 + i * 8.0
				out.append(_l([[2, v], [18, v]], 1.0, Color(W, 0.6)))
				out.append(_l([[v, 2], [v, 18]], 1.0, Color(W, 0.6)))
			if name == "m_sel_loop":
				out.append(_l([[1, 10], [19, 10]], 2.2, GOLD))
			else:
				for v in [2.0, 10.0, 18.0]:
					out.append(_l([[v, 2.5], [v, 9.5]], 2.2, GOLD))
			return out
		"m_dissolve":   # four faces made one: their inner edges fading away
			return [_f([[2, 2], [18, 2], [18, 18], [2, 18]], Color(BLUE, 0.55)), _l([[2, 2], [18, 2], [18, 18], [2, 18], [2, 2]], 1.5, W),
				_l([[10, 2], [10, 6]], 1.0, Color(W, 0.5)), _l([[10, 14], [10, 18]], 1.0, Color(W, 0.5)),
				_l([[2, 10], [6, 10]], 1.0, Color(W, 0.5)), _l([[14, 10], [18, 10]], 1.0, Color(W, 0.5)),
				_c(Vector2(10, 10), 1.2, Color(GOLD, 0.5)), _c(Vector2(7.5, 7.5), 0.8, Color(GOLD, 0.35)), _c(Vector2(12.5, 12.5), 0.8, Color(GOLD, 0.35))]
		"m_ngons":   # a pentagon whole, its triangles' diagonals faint
			var pent := [[10, 2], [18, 8], [15, 18], [5, 18], [2, 8]]
			return [_f(pent, Color(BLUE, 0.5)), _l([[10, 2], [15, 18]], 0.8, Color(W, 0.3)), _l([[10, 2], [5, 18]], 0.8, Color(W, 0.3)),
				_l(pent + [[10, 2]], 1.5, W), _c(Vector2(10, 2), 1.4, GOLD), _c(Vector2(18, 8), 1.4, GOLD), _c(Vector2(15, 18), 1.4, GOLD),
				_c(Vector2(5, 18), 1.4, GOLD), _c(Vector2(2, 8), 1.4, GOLD)]
		"m_subdivide":
			return [_f([[3, 3], [17, 3], [17, 17], [3, 17]], Color(BLUE, 0.4)), _l([[3, 3], [17, 3], [17, 17], [3, 17], [3, 3]], 1.4, W),
				_l([[10, 3], [10, 17]], 1.1, GOLD), _l([[3, 10], [17, 10]], 1.1, GOLD)]
		"m_merge":
			return _arrow(Vector2(2, 3), Vector2(7.5, 8.5), BLUE) + _arrow(Vector2(18, 3), Vector2(12.5, 8.5), BLUE) + _arrow(Vector2(10, 19), Vector2(10, 13), BLUE) \
				+ [_c(Vector2(10, 10), 2.6, GOLD)]
		"m_flip":
			return [_l([[2, 10], [18, 10]], 1.6, W)] + _arrow(Vector2(7, 10), Vector2(7, 2), GOLD) + _arrow(Vector2(13, 10), Vector2(13, 18), BLUE)
		"m_normals":
			return [_l([[2, 16], [7, 13], [13, 13], [18, 16]], 1.6, W)] + _arrow(Vector2(4.5, 14.5), Vector2(2.5, 6), GOLD, 1.3) \
				+ _arrow(Vector2(10, 13), Vector2(10, 3), GOLD, 1.3) + _arrow(Vector2(15.5, 14.5), Vector2(17.5, 6), GOLD, 1.3)
		"m_box":
			return _cube()
		"m_cylinder":
			return [_f([[4, 5], [16, 5], [16, 15], [4, 15]], Color(BLUE, 0.55)), {"pts": Icons.arc(Vector2(10, 15), 6, 0, PI, 12), "fill": Color(BLUE, 0.55)},
				_ring(Vector2(10, 5), 6, 1.2, W), _l([[4, 5], [4, 15]], 1.2, W), _l([[16, 5], [16, 15]], 1.2, W),
				{"pts": Icons.arc(Vector2(10, 15), 6, 0, PI, 12), "stroke": W, "width": 1.2, "closed": false}]
		"m_cone":
			return [_f([[10, 2], [17, 15], [3, 15]], Color(BLUE, 0.55)), {"pts": Icons.arc(Vector2(10, 15), 7, 0, PI, 12), "fill": Color(BLUE, 0.55)},
				_l([[3, 15], [10, 2], [17, 15]], 1.2, W), {"pts": Icons.arc(Vector2(10, 15), 7, 0, PI, 12), "stroke": W, "width": 1.2, "closed": false}]
		"m_materials":   # three shaded balls: the material library
			return _ball(Vector2(6, 13), 4.5, BLUE) + _ball(Vector2(14, 13), 4.5, Color(0.75, 0.42, 0.14)) + _ball(Vector2(10, 6), 4.5, GOLD)
		"m_mat_new":   # a ball and a plus
			return _ball(Vector2(8.5, 10), 6.5, BLUE) + [_c(Vector2(15.5, 15.5), 4.2, GOLD), _l([[15.5, 13], [15.5, 18]], 1.6, INK), _l([[13, 15.5], [18, 15.5]], 1.6, INK)]
		"m_mat_duplicate":   # a ball and its copy behind it
			return [_ring(Vector2(13, 7), 5.0, 1.2, Color(W, 0.6))] + _ball(Vector2(8, 12.5), 5.5, BLUE)
		"m_mat_rename":   # a ball and a pen writing its name
			return _ball(Vector2(7.5, 8), 5.5, BLUE) + [_l([[3, 18], [17, 18]], 1.2, Color(W, 0.6)), _l([[11, 16], [18, 9]], 2.4, GOLD), _f([[10, 17], [11, 16], [12, 17]], W)]
		"m_mat_delete":   # a ball crossed out
			return _ball(Vector2(9, 10), 6.5, BLUE) + [_l([[12.5, 12.5], [18, 18]], 2.0, RED), _l([[18, 12.5], [12.5, 18]], 2.0, RED)]
		"m_mat_assign":   # a ball poured onto a face
			return _ball(Vector2(10, 5.5), 4.5, GOLD) + _arrow(Vector2(10, 10.5), Vector2(10, 14), W, 1.4) + [_f([[2, 15], [18, 15], [15, 19], [5, 19]], Color(BLUE, 0.7))]
		"m_sphere":
			return [_c(Vector2(10, 10), 7.5, Color(BLUE, 0.55)), _ring(Vector2(10, 10), 7.5, 1.2, W),
				{"pts": Icons.arc(Vector2(10, 10), 7.5, 0, PI, 16), "stroke": Color(W, 0.6), "width": 1.0, "closed": false},
				_c(Vector2(7.5, 7), 1.6, GOLD)]
		"m_plane":
			return [_f([[2, 12], [10, 7], [18, 12], [10, 17]], Color(BLUE, 0.55)), _l([[2, 12], [10, 7], [18, 12], [10, 17], [2, 12]], 1.2, W)]
		"m_torus":
			return [_ring(Vector2(10, 10), 6.0, 3.6, Color(BLUE, 0.7)), _ring(Vector2(10, 10), 8.0, 1.0, W), _ring(Vector2(10, 10), 4.0, 1.0, W)]
		"m_mirror_x", "m_mirror_y", "m_mirror_z":
			var a := ["m_mirror_x", "m_mirror_y", "m_mirror_z"].find(name)
			var tri: Array = [[[8, 4], [8, 16], [2, 10]], [[4, 8], [16, 8], [10, 2]], [[8.5, 8.5], [3, 9], [8, 3]]][a]
			var tri2: Array = [[[12, 4], [12, 16], [18, 10]], [[4, 12], [16, 12], [10, 18]], [[11.5, 11.5], [17, 11], [12, 17]]][a]
			var axis: Array = [[[10, 1], [10, 19]], [[1, 10], [19, 10]], [[2, 18], [18, 2]]][a]
			return [_f(tri, BLUE), _f(tri2, Color(BLUE, 0.45)), _l(axis, 1.4, AX[a])]
		"m_mirror_apply":
			return [_f([[8, 4], [8, 16], [2, 10]], BLUE), _f([[12, 4], [12, 16], [18, 10]], BLUE), _l([[10, 1], [10, 19]], 1.4, AX[0]),
				_l([[11, 15], [13.5, 17.5], [18.5, 12.5]], 2.0, GREEN)]
		"m_sym_x", "m_sym_y", "m_sym_z":
			var a := ["m_sym_x", "m_sym_y", "m_sym_z"].find(name)
			var p: Array = [[Vector2(4, 10), Vector2(16, 10)], [Vector2(10, 4), Vector2(10, 16)], [Vector2(4, 16), Vector2(16, 4)]][a]
			var axis: Array = [[[10, 2], [10, 18]], [[2, 10], [18, 10]], [[3, 3], [17, 17]]][a]
			return [_l(axis, 1.4, AX[a]), _l([[p[0].x, p[0].y], [p[1].x, p[1].y]], 1.0, Color(W, 0.5)), _c(p[0], 2.6, GOLD), _c(p[1], 2.6, GOLD)]
		"m_symmetrize", "m_symmetrize_back":
			var back := name == "m_symmetrize_back"
			return [_f([[11, 3], [17, 10], [11, 17]] if not back else [[9, 3], [3, 10], [9, 17]], BLUE), _l([[10, 1], [10, 19]], 1.4, AX[0])] \
				+ _arrow(Vector2(14, 10) if not back else Vector2(6, 10), Vector2(3, 10) if not back else Vector2(17, 10), GOLD)
		"m_prop":
			return [_c(Vector2(10, 10), 8.5, Color(BLUE, 0.18)), _c(Vector2(10, 10), 6.0, Color(BLUE, 0.3)), _c(Vector2(10, 10), 3.6, Color(BLUE, 0.6)), _c(Vector2(10, 10), 1.8, GOLD)]
		"m_falloff":
			return [_l([[2, 17], [18, 17]], 1.0, Color(W, 0.5)), _l([[2, 17], [5, 15.5], [7.5, 9], [10, 3], [12.5, 9], [15, 15.5], [18, 17]], 1.8, GOLD)]
		"m_connected":
			return [_l([[3, 15], [8, 6], [14, 9], [17, 3]], 1.4, BLUE), _c(Vector2(3, 15), 2.2, GOLD), _c(Vector2(8, 6), 2.2, W), _c(Vector2(14, 9), 2.2, W), _c(Vector2(17, 3), 2.2, W),
				_c(Vector2(15, 16), 1.8, Color(W, 0.3))]
		"m_vertex":
			return _cube() + [_c(Vector2(10, 9), 2.2, GOLD), _c(Vector2(3, 5.5), 1.6, GOLD), _c(Vector2(17, 5.5), 1.6, GOLD), _c(Vector2(10, 18), 1.6, GOLD)]
		"m_edge":
			return _cube() + [_l([[10, 9], [10, 18]], 2.4, GOLD)]
		"m_face":
			return _cube(0)
		"m_object":
			return [_f([[10, 2], [17, 5.5], [10, 9], [3, 5.5]], GOLD), _f([[3, 5.5], [10, 9], [10, 18], [3, 14.5]], BLUE), _f([[17, 5.5], [10, 9], [10, 18], [17, 14.5]], Color(0.75, 0.42, 0.14))]
		"m_edit":
			return _cube() + [_c(Vector2(3, 5.5), 1.5, GOLD), _c(Vector2(10, 2), 1.5, GOLD), _c(Vector2(17, 5.5), 1.5, GOLD), _c(Vector2(10, 9), 1.5, GOLD),
				_c(Vector2(3, 14.5), 1.5, GOLD), _c(Vector2(17, 14.5), 1.5, GOLD), _c(Vector2(10, 18), 1.5, GOLD)]
		"m_frame", "m_frame_all":
			var out := [_l([[2, 6], [2, 2], [6, 2]], 1.6, W), _l([[14, 2], [18, 2], [18, 6]], 1.6, W), _l([[18, 14], [18, 18], [14, 18]], 1.6, W), _l([[6, 18], [2, 18], [2, 14]], 1.6, W)]
			if name == "m_frame":
				out.append(_c(Vector2(10, 10), 3.0, GOLD))
			else:
				out += [_f([[10, 5], [14.5, 7.5], [10, 10], [5.5, 7.5]], GOLD), _f([[5.5, 7.5], [10, 10], [10, 15], [5.5, 12.5]], BLUE), _f([[14.5, 7.5], [10, 10], [10, 15], [14.5, 12.5]], Color(0.75, 0.42, 0.14))]
			return out
		"m_front":
			return _cube(1)
		"m_side":
			return _cube(2)
		"m_top":
			return _cube(0, Color(0.4, 0.65, 1.0))
		"m_ortho":
			return [_l([[2, 6], [18, 6]], 1.2, BLUE), _l([[2, 10], [18, 10]], 1.2, BLUE), _l([[2, 14], [18, 14]], 1.2, BLUE),
				_l([[6, 2], [6, 18]], 1.2, W), _l([[14, 2], [14, 18]], 1.2, W)]
		"m_sel_all", "m_sel_none", "m_sel_invert":
			var out := [_l([[2, 2], [5, 2]], 1.2, W), _l([[8, 2], [12, 2]], 1.2, W), _l([[15, 2], [18, 2], [18, 5]], 1.2, W), _l([[18, 8], [18, 12]], 1.2, W),
				_l([[18, 15], [18, 18], [15, 18]], 1.2, W), _l([[12, 18], [8, 18]], 1.2, W), _l([[5, 18], [2, 18], [2, 15]], 1.2, W), _l([[2, 12], [2, 8]], 1.2, W), _l([[2, 5], [2, 2]], 1.2, W)]
			for i in 4:
				var c := Vector2(7 + (i % 2) * 6, 7 + (i / 2) * 6)
				var on := name == "m_sel_all" or (name == "m_sel_invert" and i % 3 == 0)
				out.append(_c(c, 2.0, GOLD) if on else _ring(c, 1.8, 1.0, Color(W, 0.6)))
			return out
	return []


## Label `l` with tooltip `tip` (a label takes the mouse for it: a section's heading says what the section is).
static func tipped(l: Label, tip: String) -> Label:
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	return l
