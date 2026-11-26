extends Control
## The Ship Computer (Tab, opening on the Inventory): tabbed window with the
## Inventory, the sector Map (M), the Galaxy (G), Quest, Tech Tree, Repair
## (the Repair Bay) and the Archive (every book). The game goes on while it's
## open (only the Esc menu pauses); it closes by itself when you're hit
## (Main.close_menus_on_hit).

const TABS := ["INVENTORY", "MAP", "GALAXY", "QUEST", "TECH TREE", "REPAIR", "ARCHIVE", "INDUSTRY"]
const INVENTORY_TAB := 0
const MAP_TAB := 1
const GALAXY_TAB := 2
const QUEST_TAB := 3
const TECH_TAB := 4
const REPAIR_TAB := 5
const ARCHIVE_TAB := 6
const INDUSTRY_TAB := 7
const PAGES := [
	preload("res://scripts/pages/inventory_page.gd"),
	preload("res://scripts/pages/map_page.gd"),
	preload("res://scripts/pages/galaxy_page.gd"),
	preload("res://scripts/pages/quest_page.gd"),
	preload("res://scripts/pages/tech_page.gd"),
	preload("res://scripts/repair_bay.gd"),
	preload("res://scripts/archive.gd"),
	preload("res://scripts/pages/industry_page.gd"),
]

var data: Node
var ship: Node2D

var current := 0
var _bar: HBoxContainer
var _header: Control
var _pages: Array[Control] = []


func _ready() -> void:
	hide()
	set_anchors_preset(PRESET_FULL_RECT)
	Keybinds.register_menu(self)   # (WASD / D-pad move the focus; Q / E or LB / RB switch tabs)


func cycle_tab(d: int) -> void:
	show_tab(wrapi(current + d, 0, TABS.size()))


## Pages are built on first open (they need data/ship set by the game).
func _build() -> void:
	var root := UI.modal(self, Color(NeonTheme.TEXT_DIM, 0.9), Vector2.ZERO, true)

	var header := HBoxContainer.new()
	header.add_child(UI.label("SHIP COMPUTER", 28, NeonTheme.HEAD))
	header.add_child(UI.spacer())
	header.add_child(UI.label("1-8 switch tabs  ·  M map  ·  G galaxy  ·  F1 pilot's guide  ·  Tab / Esc to close  ·  hover any icon for help", 14, UI.TEXT_DIM))
	header.add_child(EditorIcons.docs_button(self, "computer", EditorDocs.GAME))
	header.add_child(EditorIcons.dress(UI.button("", close), "close", EditorIcons.tip("Close the Ship Computer", "Tab  ·  Esc", "Closes this window (the game goes on while it's open - it closes by itself if you're attacked).\nTab, I, or M / G on their own tabs also close it.")))
	root.add_child(header)

	_bar = UI.tab_bar(TABS, show_tab)
	var tab_info := [["ui_cargo", "Everything you carry: cargo, loot, missiles and repair kits, and your fitted equipment."],
		["ui_system", "The map of this sector: stations, planets, ships, asteroids and your objective."],
		["ui_galaxy", "The galaxy map: every system, who owns it, routes between them, diplomacy and news."],
		["ui_journal", "The main quest's journal: chapters, the current objective and what happened so far."],
		["ui_tech", "Research upgrades with Data Cores: stronger weapons, shields and engines."],
		["repair", "The Repair Bay: scan your ship's and automaton's parts for faults and repair them by hand - welding, soldering, sealing, calibrating, fitting spare parts."],
		["ui_codex", "The Archive: every book of the game in one place - the pilot's guide, the tutorial, the encyclopedia of what you've discovered, the controls, the versions and the Talos manual. Search them all at once."],
		["ui_industry", "The ship's industry: the refinery turns mined fragments into minerals, the fabricator makes things from them, Upgrade Kits fit upgrades yourself."]]
	for i in _bar.get_child_count():
		EditorIcons.dress_tab(_bar.get_child(i), tab_info[i][0], EditorIcons.tip(TABS[i].capitalize(), str(i + 1) + ("  ·  M" if i == MAP_TAB else ("  ·  G" if i == GALAXY_TAB else "")), tab_info[i][1]))
	root.add_child(_bar)

	# Pages scroll when large text makes them bigger than the window.
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
	_content = content
	for script in PAGES:
		_pages.append(null)   # (each page built the first time its tab shows: page())
	data.changed.connect(_refresh_current)
	Settings.text_scale_changed.connect(_refresh_current)


## Made ahead, unseen (a scene built a piece a frame under the loading veil -
## main.gd): the window, then the pages the keys open directly (Tab / I: the
## inventory with its slots and their icons baked; M: the map; G: the galaxy)
## one a frame - a page made at its first showing was the long frame of a
## first Tab or G (the galaxy: 20 ms to make, then as much to draw).
## Each step a frame of its own (all in one: a 40-60 ms frame): the window,
## the inventory page, then the window shown for two frames unseen (its layout
## and text done now, not in the frame of the first Tab - MenuBackdrop leaves
## it be: "prewarm"), the slots' icons a few ms a frame, then the maps.
const ICONS_US := 3000
var _warming := false

func prewarm() -> void:
	if data == null or not is_inside_tree():
		return
	if _pages.is_empty():
		_build()
		await get_tree().process_frame
		if not is_inside_tree():
			return
	var p := page(INVENTORY_TAB)
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if not visible:
		_warming = true
		set_meta("prewarm", true)
		modulate.a = 0.01   # (all but invisible - but drawn: at 0 it's skipped, and nothing's made ahead)
		show()
		show_tab(INVENTORY_TAB)
		await get_tree().process_frame
		if not is_inside_tree() or not _warming:
			return
		HexReveal.play(self)   # (its curtain too: every part drawn through its shader once - their pipelines made now)
		for i in 2:
			await get_tree().process_frame
			if not is_inside_tree() or not _warming:
				return
		_end_warming(true)
	var t0 := Time.get_ticks_usec()
	for s in p.find_children("*", "", true, false):
		var id = s.get("item_id")
		if id is String and id != "":
			Items.icon_texture(id, s.get("dim") == true)
		if Time.get_ticks_usec() - t0 > ICONS_US:
			await get_tree().process_frame
			if not is_inside_tree():
				return
			t0 = Time.get_ticks_usec()
	for tab in [MAP_TAB, GALAXY_TAB]:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		page(tab)


## The unseen showing over (prewarm) - or cut short: opened or closed meanwhile.
func _end_warming(hide_it: bool) -> void:
	if not _warming:
		return
	_warming = false
	HexReveal.stop(self)
	if hide_it:
		hide()
	remove_meta("prewarm")
	modulate.a = 1.0


## Opens on `tab` - the Inventory unless told otherwise (Tab, I); M / G open
## it on the maps.
func open(tab := INVENTORY_TAB) -> void:
	_end_warming(true)   # (shown unseen just now: opened for real - the backdrop and the curtain too)
	if _pages.is_empty():
		_build()
	var was_open := visible and not HexReveal.closing(self)
	show()
	show_tab(INVENTORY_TAB if tab < 0 else tab)
	if not was_open:
		HexReveal.play(self)   # (a curtain of hexagon tiles reveals it - or, closing, turns round)


## Closes it - the hexagon curtain backwards, then hidden.
func close() -> void:
	if _warming:
		_end_warming(true)
		return
	if not visible:
		return
	if HexReveal.closing(self):
		open(current)   # (Tab again while it closes: it turns round)
		return
	HexReveal.play(self, true, hide)


func show_tab(index: int) -> void:
	current = index
	UI.select_tab(_bar, index)
	page(index)
	for i in _pages.size():
		if _pages[i] != null:
			_pages[i].visible = i == index
	_refresh_current()


var _content: Control

## Page `index` - built now if it hasn't been yet (opening the computer built
## all seven at once: a long first frame).
func page(index: int) -> Control:
	if _pages[index] == null:
		var p: Control = PAGES[index].new()
		p.data = data
		p.ship = ship
		p.hide()
		_content.add_child(p)
		_pages[index] = p
	return _pages[index]


func _refresh_current() -> void:
	if visible and not _pages.is_empty() and _pages[current] != null:
		_pages[current].refresh()
		# Menus & panels text size (pages rebuild rows on refresh). The header
		# and tabs stop at 150% so they always fit; the pages scroll.
		UI.scale_fonts(_pages[current], "menu")
		UI.scale_fonts(_header, "menu", 1.5)
		UI.scale_fonts(_bar, "menu", 1.5)


# _input (not _unhandled_input) so Tab isn't swallowed by GUI focus navigation.
func _input(event: InputEvent) -> void:
	if not visible or _warming or UI.esc_menu_open():
		return  # the Esc menu on top handles input
	if event.is_action_pressed("ui_cancel"):
		close()   # (Esc or pad B closes it - Esc again: the Esc menu)
	elif Keybinds.pressed(event, "computer") or Keybinds.pressed(event, "inventory"):
		close()
	elif Keybinds.pressed(event, "trade_layer") and current in [MAP_TAB, GALAXY_TAB]:
		_pages[current].toggle_trade()
	elif Keybinds.pressed(event, "sector_map"):
		if current == MAP_TAB:
			close()
		else:
			show_tab(MAP_TAB)
	elif Keybinds.pressed(event, "galaxy_map"):
		if current == GALAXY_TAB:
			close()
		else:
			show_tab(GALAXY_TAB)
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode >= KEY_1 and event.keycode < KEY_1 + TABS.size():
		show_tab(event.keycode - KEY_1)
	else:
		return
	get_viewport().set_input_as_handled()
