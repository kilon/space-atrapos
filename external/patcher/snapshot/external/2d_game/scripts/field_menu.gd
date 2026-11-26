extends Control
## The Field Computer (Tab, on a planet's surface): the pilot's own tabbed
## window, like the Ship Computer in space - Quest, Inventory (what you
## carry, your rifle and health), Bestiary (the planet's wildlife you've met
## and hunted), the Repair Bay, the Archive (every book), the planet Map (M) and the Spell Book (K: the
## automaton's skills - Skills, SkillBookPage). The game goes on while
## it's open (only the Esc menu pauses); it closes by itself when you're hit
## (PlanetSurface.close_menus_on_hit).

const TABS := ["QUEST", "INVENTORY", "REPAIR", "BESTIARY", "ARCHIVE", "MAP", "SKILLS"]
const SKILLS_TAB := 6
const ARCHIVE_TAB := 4
const INVENTORY_TAB := 1
const REPAIR_TAB := 2
const MAP_TAB := 5
const PAGES := [
	preload("res://scripts/pages/quest_page.gd"),
	preload("res://scripts/pages/field_inventory_page.gd"),
	preload("res://scripts/repair_bay.gd"),
	preload("res://scripts/pages/bestiary_page.gd"),
	preload("res://scripts/archive.gd"),
]

var surface: Node
var current := INVENTORY_TAB
var _bar: HBoxContainer
var _header: Control
var _pages: Array[Control] = []
var _t := 0.0


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)   # (made in code: the whole window, not a 0 x 0 box)
	Keybinds.register_menu(self)   # (WASD / D-pad move the focus; Q / E or LB / RB switch tabs)


func cycle_tab(d: int) -> void:
	show_tab(wrapi(current + d, 0, TABS.size()))


func _build() -> void:
	var root := UI.modal(self, Color(0.3, 0.9, 0.6, 0.9), Vector2.ZERO, true)
	var header := HBoxContainer.new()
	header.add_child(UI.label("FIELD COMPUTER", 28, NeonTheme.HEAD))
	header.add_child(UI.spacer())
	header.add_child(UI.label("1-7 switch tabs  ·  I inventory  ·  M map  ·  K skills  ·  Tab / Esc to close", 14, UI.TEXT_DIM))
	header.add_child(EditorIcons.docs_button(self, "planets", EditorDocs.GAME))
	header.add_child(EditorIcons.dress(UI.button("", close), "close", EditorIcons.tip("Close the Field Computer", "Tab  ·  Esc",
		"Closes this window (the game goes on while it's open - it closes by itself if you're attacked).")))
	root.add_child(header)
	_bar = UI.tab_bar(TABS, show_tab)
	var tab_info := [["ui_journal", "The main quest's journal: chapters, the current objective and what happened so far."],
		["ui_cargo", "What you carry on foot: your rifle, health, and every item - click medicine or an energy cell to use it."],
		["repair", "The Repair Bay: scan your automaton's (and your landed ship's) parts for faults and repair them by hand."],
		["ui_codex", "This planet's wildlife: the creatures you've met, how they behave, and how many you've hunted."],
		["ui_codex", "The Archive: every book of the game in one place - the guide, the tutorial, the encyclopedia of what you've discovered, the controls."],
		["ui_system", "The planet map: villages, gates, your ship and where you've explored (M)."],
		["ui_codex", "The Spell Book: your martial arts, the leap and the arcana - learn them and raise their ranks with the skill points your levels give, and put them on the toolbar (K)."]]
	for i in _bar.get_child_count():
		EditorIcons.dress_tab(_bar.get_child(i), tab_info[i][0], EditorIcons.tip(TABS[i].capitalize(), str(i + 1) + ("  ·  M" if i == MAP_TAB else "  ·  K" if i == SKILLS_TAB else ""), tab_info[i][1]))
	root.add_child(_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	root.add_child(scroll)
	_header = header
	var content := MarginContainer.new()
	content.add_theme_constant_override("margin_top", 8)
	content.size_flags_horizontal = SIZE_EXPAND_FILL
	content.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.add_child(content)
	for script in PAGES:
		var page: Control = script.new()
		if "surface" in page:
			page.surface = surface
		page.hide()
		content.add_child(page)
		_pages.append(page)
	# The planet map: a page of its own (SurfaceMap, embedded).
	var map := SurfaceMap.new()
	map.embedded = true
	map.surface = surface
	map.hide()
	content.add_child(map)
	_pages.append(map)
	# The Spell Book (after the map: the tabs before it keep their numbers).
	var book: Control = preload("res://scripts/pages/skill_book_page.gd").new()
	book.surface = surface
	book.hide()
	content.add_child(book)
	_pages.append(book)
	Settings.text_scale_changed.connect(_refresh_current)


func open(tab := -1) -> void:
	if _pages.is_empty():
		_build()
	var was_open := visible and not HexReveal.closing(self)
	show()
	show_tab(current if tab < 0 else tab)
	if not was_open:
		HexReveal.play(self)   # (a curtain of hexagon tiles reveals it - or, closing, turns round)


## Closes it - the hexagon curtain backwards, then hidden.
func close() -> void:
	if not visible:
		return
	if HexReveal.closing(self):
		open(current)   # (Tab again while it closes: it turns round)
		return
	HexReveal.play(self, true, hide)


func show_tab(index: int) -> void:
	current = index
	UI.select_tab(_bar, index)
	for i in _pages.size():
		_pages[i].visible = i == index
	_refresh_current()


func _refresh_current() -> void:
	if visible and not _pages.is_empty():
		_pages[current].refresh()
		UI.scale_fonts(self, "menu")
		UI.scale_fonts(_header, "menu", 1.5)
		UI.scale_fonts(_bar, "menu", 1.5)


## (the inventory's counts and health change as you play: kept current)
func _process(delta: float) -> void:
	if not visible:
		return
	_t -= delta
	if _t <= 0.0 and current in [INVENTORY_TAB, SKILLS_TAB]:
		_t = 0.5
		_pages[current].refresh()


# _input (not _unhandled_input) so Tab isn't swallowed by GUI focus navigation.
func _input(event: InputEvent) -> void:
	if not visible or UI.esc_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		close()   # (Esc or pad B closes it - Esc again: the Esc menu)
	elif Keybinds.pressed(event, "computer"):
		close()
	elif Keybinds.pressed(event, "inventory"):
		if current == INVENTORY_TAB:
			close()
		else:
			show_tab(INVENTORY_TAB)
	elif Keybinds.pressed(event, "sector_map"):
		if current == MAP_TAB:
			close()
		else:
			show_tab(MAP_TAB)
	elif Keybinds.pressed(event, "skills"):
		if current == SKILLS_TAB:
			close()
		else:
			show_tab(SKILLS_TAB)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode < KEY_1 + TABS.size():
		show_tab(event.keycode - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()
