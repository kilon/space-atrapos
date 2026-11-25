extends TestCase
## Text stays readable and at the player's size: on every page of every
## menu, at 130% "Menus & panels" text, after the page is rebuilt (what a
## purchase, an equip, a mission accepted does), every text control is at
## its screen's size (UI.scale_fonts' mark; UI.fit_text for text added
## later) - none back at 100% - and none, anywhere on screen (HUDs too), is
## under Settings.MIN_FONT.

const SCALE := 1.3


func _settle() -> void:
	for i in 3:
		await tree.process_frame


## Text controls showing under `root` whose size isn't their screen's (the
## nearest ancestor UI.scale_fonts marked) - e.g. built after the screen was
## scaled and never scaled themselves.
func _unscaled(root: Node) -> Array:
	var out := []
	for n in root.find_children("*", "Control", true, false):
		var keys := UI._text_keys(n)
		if keys.is_empty() or not n.is_visible_in_tree():
			continue
		var mark: Array = []
		var p: Node = n
		while p != null:
			if p.has_meta("fixed_font"):
				break
			if p.has_meta("text_scale"):
				mark = p.get_meta("text_scale")
				break
			p = p.get_parent()
		if mark.is_empty():
			continue
		var s := minf(Settings.font_scale(str(mark[0])), float(mark[1]))
		var key: String = keys[0]
		if not n.has_meta("base_" + key):
			out.append("%s (%s): never scaled" % [n.name, _text(n)])
			continue
		var want := maxi(Settings.MIN_FONT, roundi(n.get_meta("base_" + key) * s))
		if n.get_theme_font_size(key) != want:
			out.append("%s (%s): %d, not %d" % [n.name, _text(n), n.get_theme_font_size(key), want])
	return out


## Text controls showing under `root` smaller than Settings.MIN_FONT.
func _small(root: Node) -> Array:
	var out := []
	for n in root.find_children("*", "Control", true, false):
		var keys := UI._text_keys(n)
		if keys.is_empty() or not n.is_visible_in_tree():
			continue
		if n.get_theme_font_size(keys[0]) < Settings.MIN_FONT:
			out.append("%s (%s): %d px" % [n.name, _text(n), n.get_theme_font_size(keys[0])])
	return out


func _text(n: Control) -> String:
	var t := str(n.get("text")) if n.get("text") != null else ""
	return t.left(30).replace("\n", " ")


func _check(root: Node, what: String) -> void:
	var u := _unscaled(root)
	check(u.is_empty(), "%s: text not at the screen's size: %s" % [what, u.slice(0, 6)])
	var sm := _small(root)
	check(sm.is_empty(), "%s: text under %d px: %s" % [what, Settings.MIN_FONT, sm.slice(0, 6)])


func test_every_page_keeps_its_text_size() -> void:
	Settings.set_text_scale("menu", SCALE)
	var old_size: Vector2i = tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	await _settle()
	_check(main.hud, "the space HUD")
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	main.station_menu.open(st)
	for t in main.station_menu.TABS.size():
		main.station_menu.show_tab(t)
		await _settle()
		main.player_data.changed.emit()   # (a purchase, a sale...: the page rebuilt)
		await _settle()
		_check(main.station_menu, "station tab %s, rebuilt" % main.station_menu.TABS[t])
	main.station_menu.close()
	main.ship_menu.open()
	for t in main.ship_menu.TABS.size():
		main.ship_menu.show_tab(t)
		await _settle()
		main.player_data.changed.emit()
		await _settle()
		_check(main.ship_menu, "Ship Computer tab %s, rebuilt" % main.ship_menu.TABS[t])
	main.ship_menu.close()
	main.queue_free()
	await tree.process_frame
	SaveGame.space_state = {}
	SaveGame.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	await _settle()
	_check(s, "the surface HUD")
	s.field_menu.open()
	for t in s.field_menu.TABS.size():
		s.field_menu.show_tab(t)
		await _settle()
		for p in s.field_menu.find_children("*", "LoadoutPanel", true, false):
			p.refresh()   # (an equip: the automaton's panel rebuilt)
		for i in 12:   # (the Field Computer's own refresh, twice a second)
			await tree.process_frame
		_check(s.field_menu, "Field Computer tab %s, rebuilt" % s.field_menu.TABS[t])
	s.field_menu.close()
	s.queue_free()
	await tree.process_frame
	SaveGame.landed_planet = ""
	var menu: Control = load("res://main_menu.tscn").instantiate()
	menu.overlay = true
	tree.root.add_child(menu)
	await _settle()
	menu._open_settings()
	for t in menu.SETTINGS_TABS.size():
		menu.show_settings_tab(t)
		await _settle()
		_check(menu, "settings tab %s" % menu.SETTINGS_TABS[t])
	menu.queue_free()
	await tree.process_frame
	tree.root.size = old_size
	Settings.set_text_scale("menu", 1.0)
