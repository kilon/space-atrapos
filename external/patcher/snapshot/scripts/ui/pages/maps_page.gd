extends VBoxContainer
## The Automaton's MAP tab: three maps under their own tabs - PLANET (the
## world you're on or nearest, a 3D globe under its fog of war, its towns'
## plans: PlanetMapPage), SOLAR SYSTEM (the system you're in, in 3D:
## map_page.gd) and GALAXY (New Hellas in 3D: galaxy_page.gd). M opens it on
## the planet's map on a planet, else the solar map; G on the galaxy. Each map
## is made the first time its tab shows (the Automaton makes them ahead:
## ShipMenu.prewarm).

const SUBS := ["PLANET", "SOLAR SYSTEM", "GALAXY"]
const PLANET := 0
const SOLAR := 1
const GALAXY := 2
const SCRIPTS := [
	preload("res://scripts/ui/pages/planet_map_page.gd"),
	preload("res://scripts/ui/pages/map_page.gd"),
	preload("res://scripts/ui/pages/galaxy_page.gd"),
]

var data: Node
var ship: Node2D
var world: Node                  # (the 3D game - Cosmos)
var current := SOLAR
var _bar: HBoxContainer
var _subs: Array[Control] = [null, null, null]


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = SIZE_EXPAND_FILL
	size_flags_vertical = SIZE_EXPAND_FILL
	_bar = UI.tab_bar(SUBS, show_sub, Color(), false)
	var info := [["planets", "Planet", "The world you're on or nearest (or one picked on the solar map) as a globe: what you've explored of it, its towns, caves, dungeons and camps; zoom in on a town you've been in for its plan."],
		["ui_system", "Solar system", "The system you're in, in 3D - its star, worlds, stations, gates and the ships your sensors see. Pick one for its details and set a course."],
		["ui_galaxy", "Galaxy", "The galaxy in 3D: the systems you've been in, who owns them, the lanes between them - plot a route; diplomacy and news."]]
	for i in _bar.get_child_count():
		var b := _bar.get_child(i) as Button
		b.custom_minimum_size = Vector2(150, 34)
		b.add_theme_font_size_override("font_size", 16)
		EditorIcons.dress_tab(b, info[i][0], EditorIcons.tip(info[i][1], ["M  (on a planet)", "M", "G"][i], info[i][2]))
	add_child(_bar)


## Sub map `i`, made now if it hasn't been yet.
func sub(i: int) -> Control:
	if _subs[i] == null:
		var p: Control = SCRIPTS[i].new()
		p.data = data
		p.ship = ship
		if "world" in p:
			p.world = world
		p.size_flags_vertical = SIZE_EXPAND_FILL
		p.hide()
		add_child(p)
		_subs[i] = p
	return _subs[i]


## Shows map `i` - every time centred on where you are (focus_you: the
## planet map on your spot, the solar map on you or the world you're on,
## the galaxy on your system); `keep_pick`: the world picked on the solar map.
func show_sub(i: int, refresh_it := true, keep_pick := false) -> void:
	current = i
	UI.select_tab(_bar, i)
	sub(i)
	for k in _subs.size():
		if _subs[k] != null:
			_subs[k].visible = k == i
	if refresh_it:
		_subs[i].refresh()
		UI.scale_fonts(_subs[i], "menu")
	if _subs[i].has_method("focus_you"):
		_subs[i].focus_you(keep_pick)


## The planet map on `pl` (a CosmosPlanet - picked on the solar map).
func show_planet(pl: Node) -> void:
	(sub(PLANET) as PlanetMapPage).picked = pl
	show_sub(PLANET, true, true)


func refresh() -> void:
	if _subs[current] != null:
		_subs[current].refresh()


func toggle_trade() -> void:
	var p := _subs[current]
	if p != null and p.has_method("toggle_trade"):
		p.toggle_trade()
