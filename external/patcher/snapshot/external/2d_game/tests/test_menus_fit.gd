extends TestCase
## Every menu stays inside the window: the title / pause menu and its
## settings (each tab), the CRT page, the station's tabs, the Ship Computer's
## tabs - at 100% text and at the largest text size (Settings.TEXT_SCALE_MAX).
## Checked: every visible panel not inside a scroll area (a scrolled panel may
## run past its scroll area's edge - that's what the scroll is for).


## The panels of `root` sticking out of the window: ["name: rect", ...].
func _outside(root: Control) -> Array:
	var vp := root.get_viewport().get_visible_rect().grow(1.0)
	var out := []
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is ScrollContainer:
			continue   # (its content scrolls)
		if n is Control and not n.is_visible_in_tree():
			continue
		if n is PanelContainer and not vp.encloses(n.get_global_rect()):
			out.append("%s: %s" % [n.get_path(), n.get_global_rect()])
		stack.append_array(n.get_children())
	return out


func _settle() -> void:
	for i in 3:
		await tree.process_frame


func test_settings_fit() -> void:
	for scale in [1.0, Settings.TEXT_SCALE_MAX]:
		Settings.set_text_scale("menu", scale)
		var menu: Control = load("res://main_menu.tscn").instantiate()
		menu.overlay = true   # (no attract mode, no title-screen background)
		tree.root.add_child(menu)
		await _settle()
		check(_outside(menu).is_empty(), "main buttons at %d%%: %s" % [scale * 100, _outside(menu)])
		menu._open_settings()
		for t in menu.SETTINGS_TABS.size():
			menu.show_settings_tab(t)
			await _settle()
			check(_outside(menu).is_empty(), "settings tab %s at %d%%: %s" % [menu.SETTINGS_TABS[t], scale * 100, _outside(menu)])
		menu._open_crt()
		await _settle()
		check(_outside(menu).is_empty(), "CRT page at %d%%: %s" % [scale * 100, _outside(menu)])
		menu._close_crt()
		menu.queue_free()
		await tree.process_frame
	Settings.set_text_scale("menu", 1.0)


func test_settings_tabs() -> void:
	var menu: Control = load("res://main_menu.tscn").instantiate()
	menu.overlay = true
	tree.root.add_child(menu)
	await _settle()
	menu._open_settings()
	menu.show_settings_tab(0)
	check(menu.resolution_option.is_visible_in_tree(), "DISPLAY: the resolution")
	menu.show_settings_tab(3)
	check(not menu.resolution_option.is_visible_in_tree(), "other tabs hide it")
	check(menu._bind_buttons["dock|0"].is_visible_in_tree(), "CONTROLS: the key bindings")
	menu.show_settings_tab(menu.SETTINGS_TABS.size() - 1)
	menu.cycle_tab(1)
	check_eq(menu.settings_tab, 0, "the tab keys wrap round")
	menu.queue_free()
	await tree.process_frame


func test_game_menus_fit() -> void:
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	await _settle()
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	for scale in [1.0, Settings.TEXT_SCALE_MAX]:
		Settings.set_text_scale("menu", scale)
		main.station_menu.open(st)
		for t in main.station_menu.TABS.size():
			main.station_menu.show_tab(t)
			await _settle()
			check(_outside(main.station_menu).is_empty(), "station tab %s at %d%%: %s" % [main.station_menu.TABS[t], scale * 100, _outside(main.station_menu)])
		main.station_menu.close()
		main.ship_menu.open()
		for t in main.ship_menu.TABS.size():
			main.ship_menu.show_tab(t)
			await _settle()
			check(_outside(main.ship_menu).is_empty(), "Ship Computer tab %s at %d%%: %s" % [main.ship_menu.TABS[t], scale * 100, _outside(main.ship_menu)])
		main.ship_menu.close()
	Settings.set_text_scale("menu", 1.0)
	main.queue_free()
	await tree.process_frame


func test_field_menu_fits() -> void:
	SaveGame.space_state = {}
	SaveGame.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	await _settle()
	for scale in [1.0, Settings.TEXT_SCALE_MAX]:
		Settings.set_text_scale("menu", scale)
		s.field_menu.open()
		for t in s.field_menu.TABS.size():
			s.field_menu.show_tab(t)
			await _settle()
			check(_outside(s.field_menu).is_empty(), "Field Computer tab %s at %d%%: %s" % [s.field_menu.TABS[t], scale * 100, _outside(s.field_menu)])
		s.field_menu.close()
	Settings.set_text_scale("menu", 1.0)
	s.queue_free()
	await tree.process_frame


## The scroll areas of `root` whose content is taller than they are (at
## this text size): ["name: need / have", ...]. (A Tree or ItemList that
## scrolls a long list inside a page is fine: not a ScrollContainer.)
func _scrolls(root: Control) -> Array:
	var out := []
	for sc in root.find_children("*", "ScrollContainer", true, false):
		if not sc.is_visible_in_tree() or sc.get_child_count() == 0 or sc.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			continue
		var need: Vector2 = sc.get_child(0).get_combined_minimum_size()
		if need.y > sc.size.y + 2.0:
			out.append("%s: %d / %d high" % [sc.name, need.y, sc.size.y])
		if need.x > sc.size.x + 2.0 and sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			out.append("%s: %d / %d wide" % [sc.name, need.x, sc.size.x])
	return out


## At 100% text (1920 x 1080) no page needs scrolling down to be seen whole:
## the station's tabs, the Ship Computer's, the Field Computer's, the settings.
func test_no_page_scrolls() -> void:
	await _no_page_scrolls(1.0)


## Nor at 130% "Menus & panels" text (a size players pick).
func test_no_page_scrolls_at_130() -> void:
	await _no_page_scrolls(1.3)


func test_no_page_scrolls_at_150() -> void:
	await _no_page_scrolls(1.5)


func _no_page_scrolls(scale: float) -> void:
	Settings.set_text_scale("menu", scale)
	var old_size: Vector2i = tree.root.size
	tree.root.size = Vector2i(1920, 1080)   # (headless runs are square: the real window)
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	await _settle()
	var st: Node2D = tree.get_nodes_in_group("stations")[0]
	main.station_menu.open(st)
	for t in main.station_menu.TABS.size():
		main.station_menu.show_tab(t)
		await _settle()
		check(_scrolls(main.station_menu).is_empty(), "at %d%%, station tab %s scrolls: %s" % [roundi(scale * 100), main.station_menu.TABS[t], _scrolls(main.station_menu)])
	# The outfitter's categories (each with its first card's detail) and the
	# shipyard's classes: none scrolls either.
	var sm = main.station_menu
	for q in [0, 4]:   # (the quality's buttons show on two of them)
		sm._quality = q
		for i in sm.OUTFIT_TABS.size():
			sm._outfit_tab = i
			sm._outfit_sel = ""
			sm.show_tab(sm.TABS.find("OUTFITTING"))
			await _settle()
			check(_scrolls(sm).is_empty(), "at %d%%, outfitting > %s scrolls: %s" % [roundi(scale * 100), sm.OUTFIT_TABS[i], _scrolls(sm)])
	for i in TradeRoutes.CATEGORIES.size():   # (the market's categories)
		MarketPage.category = i
		sm.show_tab(sm.TABS.find("MARKET"))
		await _settle()
		check(_scrolls(sm).is_empty(), "at %d%%, market > %s scrolls: %s" % [roundi(scale * 100), TradeRoutes.CATEGORIES[i][0], _scrolls(sm)])
	MarketPage.category = 0
	for i in 7:
		sm._yard_tab = i
		sm.show_tab(sm.TABS.find("SHIPYARD"))
		await _settle()
		check(_scrolls(sm).is_empty(), "at %d%%, shipyard class %d scrolls: %s" % [roundi(scale * 100), i, _scrolls(sm)])
	main.station_menu.close()
	main.ship_menu.open()
	for t in main.ship_menu.TABS.size():
		main.ship_menu.show_tab(t)
		await _settle()
		check(_scrolls(main.ship_menu).is_empty(), "at %d%%, Ship Computer tab %s scrolls: %s" % [roundi(scale * 100), main.ship_menu.TABS[t], _scrolls(main.ship_menu)])
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
	s.field_menu.open()
	for t in s.field_menu.TABS.size():
		s.field_menu.show_tab(t)
		await _settle()
		check(_scrolls(s.field_menu).is_empty(), "at %d%%, Field Computer tab %s scrolls: %s" % [roundi(scale * 100), s.field_menu.TABS[t], _scrolls(s.field_menu)])
	s.field_menu.close()
	s.queue_free()
	await tree.process_frame
	var menu: Control = load("res://main_menu.tscn").instantiate()
	menu.overlay = true
	tree.root.add_child(menu)
	await _settle()
	menu._open_settings()
	for t in menu.SETTINGS_TABS.size():
		menu.show_settings_tab(t)
		await _settle()
		check(_scrolls(menu).is_empty(), "at %d%%, settings tab %s scrolls: %s" % [roundi(scale * 100), menu.SETTINGS_TABS[t], _scrolls(menu)])
	menu._open_crt()
	await _settle()
	check(_scrolls(menu).is_empty(), "the CRT page scrolls at %d%%: %s" % [roundi(scale * 100), _scrolls(menu)])
	menu.queue_free()
	await tree.process_frame
	tree.root.size = old_size
	Settings.set_text_scale("menu", 1.0)


## The event log never runs under the toolbar - in space and on foot, at
## every HUD text size, on a full-HD screen and a smaller one.
func test_event_log_clear_of_the_toolbar() -> void:
	var old_size: Vector2i = tree.root.size
	for screen in [Vector2i(1920, 1080), Vector2i(1280, 720)]:
		tree.root.size = screen
		for k in [1.0, 1.3, 1.4, 1.5, 2.0]:
			Settings.set_text_scale("hud", k)
			Galaxy.new_game(false)
			var main: Node = load("res://main.tscn").instantiate()
			tree.root.add_child(main)
			for i in 4:
				await tree.process_frame
			var lr: Rect2 = main.hud.event_log.get_global_rect()
			var tr: Rect2 = main.hud.toolbar.get_global_rect()
			check(lr.end.x <= tr.position.x - 8.0, "space, %s at %d%%: the log (to x %d) clear of the toolbar (from x %d)" % [screen, k * 100, lr.end.x, tr.position.x])
			main.queue_free()
			await tree.process_frame
			SaveGame.space_state = {}
			SaveGame.landed_planet = "thalassa"
			var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
			tree.root.add_child(s)
			while not s.is_built:
				await tree.process_frame
			for i in 4:
				await tree.process_frame
			var log: Control = s.find_children("*", "GameLog", true, false)[0]
			lr = log.get_global_rect()
			tr = s.toolbar.get_global_rect()
			check(lr.end.x <= tr.position.x - 8.0, "on foot, %s at %d%%: the log (to x %d) clear of the toolbar (from x %d)" % [screen, k * 100, lr.end.x, tr.position.x])
			s.queue_free()
			await tree.process_frame
			SaveGame.landed_planet = ""
	Settings.set_text_scale("hud", 1.0)
	tree.root.size = old_size


## A mission card in the narrow active list with two buttons (Turn in and
## Abandon): its reward reads on one line - the buttons drop under it -
## and the contact's portrait keeps its size at the top.
func test_active_mission_reward_reads_across() -> void:
	var old_size: Vector2i = tree.root.size
	tree.root.size = Vector2i(1920, 1080)
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	for i in 3:
		await tree.process_frame
	var sm = main.station_menu
	sm.open(tree.get_nodes_in_group("stations")[0])
	await tree.process_frame
	for k in [1.0, 1.3, 1.5]:
		Settings.set_text_scale("menu", k)
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(380, 0)
		col.size = Vector2(380, 0)
		sm.add_child(col)
		var m := {"title": "Salvage Request", "giver": "Helios Dock", "desc": "Our workshops need 4 Alien Alloy. Bring them here.", "tier": 1, "reward_text": "600 cr"}
		var card: Control = sm._mission_card(m, [UI.button("Turn in", func(): pass, 15), UI.button("Abandon", func(): pass, 15)], "4 / 4 Alien Alloy  ·  turn in at Helios Dock")
		col.add_child(card)
		UI.scale_fonts(col, "menu")
		for i in 3:
			await tree.process_frame
		var reward: Label = null
		for l in card.find_children("*", "Label", true, false):
			if l.text.begins_with("Reward:"):
				reward = l
		check(reward != null and reward.get_line_count() == 1, "at %d%%: the reward on one line (%d lines, %d px wide)" % [k * 100, reward.get_line_count() if reward else -1, reward.size.x if reward else -1])
		var face: Control = card.find_children("*", "Portrait", true, false)[0] if not card.find_children("*", "Portrait", true, false).is_empty() else null
		if face:
			check(face.size.y < 80.0, "at %d%%: the portrait keeps its size (%d px tall in a %d px card)" % [k * 100, face.size.y, card.size.y])
		col.queue_free()
		await tree.process_frame
	Settings.set_text_scale("menu", 1.0)
	sm.close()
	main.queue_free()
	await tree.process_frame
	tree.root.size = old_size
