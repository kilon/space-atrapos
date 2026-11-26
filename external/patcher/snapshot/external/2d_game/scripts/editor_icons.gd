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
const NAMES := ["ui_industry", "ui_journal", "ui_cargo", "ui_tech", "ui_codex", "ui_guide", "ui_system", "ui_galaxy", "save", "reload", "undo", "redo", "paste", "gui", "back", "forward", "exit", "add", "up", "down", "delete", "play", "stop", "anim", "library", "zoo", "dialogue", "quest", "lore", "chat", "sprites", "characters", "ships", "stations", "planets", "nebulae", "suns", "buildings", "effects", "terrain", "building", "wall", "column", "npc", "prop", "erase", "enemy", "neutral", "asteroid", "tool", "buy", "sell", "sellall", "accept", "turnin", "abandon", "undock", "pledge", "repair", "remove", "apply", "paint", "close", "land", "next", "skip", "restart", "menu", "rating", "ship", "bake", "fit_all", "duplicate", "rename", "key", "keypose", "keydel", "prevkey", "nextkey", "docs", "help", "patch", "svg", "select", "node", "rect", "ellipse", "star_tool", "pen", "pencil", "text", "picker", "export", "open", "new", "grid", "eye", "eye_off", "lock", "unlock", "snap"]


## Paints every icon not yet on disk, on worker threads - at start-up, so no
## screen waits for its icons the first time it opens (Icons.warm).
static func warm() -> void:
	if DisplayServer.get_name() == "headless":
		return   # (no screen: nothing to paint for - and no threads left running at exit)
	for n in NAMES:
		Icons.warm(20, 20, layers_of(n))


## What icon `name` is drawn with ([] for unknown names).
static func layers_of(name: String) -> Array:
	var layers: Array = []
	match name:
		# The Ship Computer's tabs: glowing line icons, one per page.
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
		# SVG Editor.
		"patch": layers = [_f([[3, 2], [13, 2], [17, 6], [17, 18], [3, 18]], BLUE), _l([[6, 7], [12, 7]], 1.4, Color(0.1, 0.12, 0.18)), _l([[6, 10], [14, 10]], 1.4, Color(0.1, 0.12, 0.18)), _l([[6, 13], [11, 13]], 1.4, Color(0.1, 0.12, 0.18)), _c(Vector2(14.5, 15), 3.6, GOLD), _l([[13, 15], [14.3, 16.3], [16.3, 13.6]], 1.3, Color(0.1, 0.12, 0.18))]
		"svg": layers = [_f([[10, 1], [15, 9], [12, 18], [8, 18], [5, 9]], GOLD), _l([[10, 6], [10, 13]], 1.4, Color(0.1, 0.12, 0.18)), _c(Vector2(10, 13), 1.6, Color(0.1, 0.12, 0.18))]
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
	b.tooltip_text = tooltip
	return b


## Short labels for the long titles (the rest: the title itself if short,
## else its first two words).
const SHORT := {
	"Save to file": "Save", "Reload from file": "Reload", "Preview dialogue": "Preview",
	"Reload sprites": "Reload art", "Documentation": "Help", "Pilot's guide": "Guide",
	"Exit Talos": "Exit", "Exit the level editor": "Exit", "Exit preview": "Exit",
	"Close the Ship Computer": "Close", "Close the map": "Close", "Close the Field Computer": "Close",
	"Asset browser": "Browser", "Centre on your ship": "My ship", "Trade routes": "Routes",
	"Whole sector": "Whole map", "Save layout": "Save", "Load saved game": "Load",
	"Main menu": "Menu", "Pump from the hold": "Pump", "Accept mission": "Accept",
	"Test in game": "Test", "Import the main quest": "Import", "Zoom to page": "Fit page",
	"Snap to grid": "Snap", "Export PNG": "Export", "Reload patches": "Reload",
	"Open this patch": "Open patch", "Previous step": "Previous", "Next step": "Next",
	"Play the sound": "Play", "New scenario": "New", "Revert to generated": "Revert",
	"Hull fully repaired": "Repaired", "Add citizen line": "Add line", "Apply paint": "Apply",
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
