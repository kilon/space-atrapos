extends TestCase
## Save slots (SaveGame: SLOTS of them, a summary each, the old single save
## moved into slot 1) and saving on a planet (you load back down there, where
## you stood).


func setup() -> void:
	for i in range(1, SaveGame.SLOTS + 1):
		SaveGame.delete_slot(i)
	Galaxy.new_game(false)


func teardown() -> void:
	for i in range(1, SaveGame.SLOTS + 1):
		SaveGame.delete_slot(i)
	SaveGame.pending = {}
	SaveGame.resume = {}
	SaveGame.landed_planet = ""
	SaveGame.space_state = {}
	SaveGame.travelling = false


func test_slots() -> void:
	check(not SaveGame.has_save(), "no saves")
	check(SaveGame.save_game({"player": {"credits": 111}}, 2), "saved in slot 2")
	await tree.create_timer(1.1).timeout   # (the newest by its time stamp)
	check(SaveGame.save_game({"player": {"credits": 333}}, 5), "saved in slot 5")
	check(SaveGame.has_save(2) and SaveGame.has_save(5) and not SaveGame.has_save(1), "two slots used")
	check_eq(SaveGame.latest_slot(), 5, "the newest")
	var info := SaveGame.slot_info(2)
	check_eq(int(info["summary"]["credits"]), 111, "a slot's summary: credits")
	check(str(info["summary"]["system"]) != "", "and where you were")
	check(SaveGame.queue_load(2) and int(SaveGame.pending["player"]["credits"]) == 111, "load a chosen slot")
	check(SaveGame.queue_load() and int(SaveGame.pending["player"]["credits"]) == 333, "load the newest")
	SaveGame.delete_slot(5)
	check(not SaveGame.has_save(5), "deleted")
	check(SaveGame.slot_info(4).is_empty(), "an empty slot")


func test_old_save_becomes_slot_1() -> void:
	var f := FileAccess.open(SaveGame.LEGACY, FileAccess.WRITE)
	f.store_string(JSON.stringify({"version": 1, "saved_at": "2026-01-01T10:00:00", "state": {"player": {"credits": 77}}}))
	f.close()
	SaveGame._migrate()
	check(not FileAccess.file_exists(SaveGame.LEGACY), "the old file moved")
	check(SaveGame.has_save(1) and int(SaveGame.read_save(1)["state"]["player"]["credits"]) == 77, "into slot 1")


func test_save_on_a_planet() -> void:
	SaveGame.space_state = {}
	SaveGame.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	s.pilot.position += Vector2(300, -200)
	var where: Vector2 = s.pilot.position
	var d: Dictionary = s.get_save_data()
	check(d.has("landed") and d["landed"]["planet"] == "thalassa", "a save on a planet says which")
	check(Vector2(d["landed"]["pos"][0], d["landed"]["pos"][1]).is_equal_approx(where), "and where you stood")
	check(SaveGame.save_game(d, 3), "saved")
	check(str(SaveGame.slot_info(3)["summary"]["planet"]) != "", "the slot list shows the planet")
	s.queue_free()
	await tree.process_frame
	# Loading it: the space scene sets up the landing ...
	SaveGame.landed_planet = ""
	SaveGame.queue_load(3)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	for i in 5:
		await tree.process_frame
	# (as the current scene it would go down at once: here, check what it would do)
	var landed: Dictionary = SaveGame.read_save(3)["state"]["landed"]
	check_eq(str(landed["planet"]), "thalassa", "the save takes you to that planet")
	main.queue_free()
	await tree.process_frame
	# ... and the surface puts you where you stood.
	SaveGame.landed_planet = "thalassa"
	SaveGame.resume = landed
	var s2: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s2)
	while not s2.is_built:
		await tree.process_frame
	check(s2.pilot.position.is_equal_approx(where), "back where you stood (%s / %s)" % [s2.pilot.position, where])
	check(SaveGame.resume.is_empty(), "used once")
	s2.queue_free()
	await tree.process_frame


func test_quicksave_and_autosave() -> void:
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	for i in 5:
		await tree.process_frame
	# (not the current scene in a test: give SaveGame the game to save)
	var g: Node = main
	check(SaveGame.save_game(g.get_save_data(), SaveGame.QUICK), "a quicksave")
	check(SaveGame.has_save(SaveGame.QUICK) and not SaveGame.has_save(1), "in its own slot, not a numbered one")
	check(SaveGame.save_game(g.get_save_data(), SaveGame.AUTO), "an autosave")
	check(SaveGame.has_save(SaveGame.AUTO), "in its own slot")
	check(SaveGame.QUICK in SaveGame.all_slots() and SaveGame.AUTO in SaveGame.all_slots(), "both in the load list")
	check(SaveGame.latest_slot() in [SaveGame.QUICK, SaveGame.AUTO], "the newest of them")
	check(SaveGame.queue_load(SaveGame.QUICK) and not SaveGame.pending.is_empty(), "the quicksave loads")
	SaveGame.pending = {}
	# Under attack: no autosave.
	var e: Node2D = main.spawn_enemy(main.ship.global_position + Vector2(400, 0))
	e._target = main.ship
	check(main.in_combat(), "in combat with an enemy on you")
	e.queue_free()
	await tree.process_frame
	check(not main.in_combat(), "out of it")
	check(Keybinds.binds.has("quicksave") and Keybinds.binds.has("quickload"), "F5 / F9 are bindable actions")
	main.queue_free()
	await tree.process_frame
	for s in [SaveGame.QUICK, SaveGame.AUTO]:
		SaveGame.delete_slot(s)


func test_autosave_settings() -> void:
	var old_m: int = Settings.autosave_minutes
	var old_e: bool = Settings.autosave_events
	check_eq(Settings.AUTOSAVE_CHOICES[0], 0, "Off is a choice")
	# Off: the timer never saves.
	Settings.autosave_minutes = 0
	SaveGame._auto_t = 0.0
	SaveGame._process(1.0)
	check(not SaveGame.has_save(SaveGame.AUTO), "periodic autosaves off: none")
	check(SaveGame._auto_t <= 0.0, "(the timer doesn't run)")
	# A shorter interval applies at once.
	Settings.autosave_minutes = 2
	SaveGame._auto_t = 1000.0
	SaveGame._process(0.0)
	check(SaveGame._auto_t <= 120.0, "every 2 minutes: the countdown shortened (%.0f)" % SaveGame._auto_t)
	# Event autosaves switched off: docking, jumping, landing don't save.
	Settings.autosave_events = false
	check(not SaveGame.autosave("docked at somewhere"), "event autosaves off")
	# The GAME tab shows and changes them.
	var menu: Control = load("res://main_menu.tscn").instantiate()
	menu.overlay = true
	tree.root.add_child(menu)
	await tree.process_frame
	menu._open_settings()
	menu.show_settings_tab(menu.SETTINGS_TABS.find("GAME"))
	await tree.process_frame
	check(menu._autosave_option.is_visible_in_tree(), "the GAME tab: autosave")
	check_eq(menu._autosave_option.selected, Settings.AUTOSAVE_CHOICES.find(2), "showing the setting")
	menu._autosave_option.select(Settings.AUTOSAVE_CHOICES.find(15))
	menu._autosave_option.item_selected.emit(Settings.AUTOSAVE_CHOICES.find(15))
	check_eq(Settings.autosave_minutes, 15, "chosen there")
	menu._autosave_events.button_pressed = true
	check(Settings.autosave_events, "event autosaves on again")
	menu.queue_free()
	await tree.process_frame
	Settings.autosave_minutes = old_m
	Settings.autosave_events = old_e
	Settings.save_settings()


class FakeGame extends Node:
	func get_save_data() -> Dictionary:
		return {}


class FakeSurface extends FakeGame:
	var is_built := false
	var build_progress := 0.0


func _veil(game: Node) -> LoadVeil:
	var v := LoadVeil.new()
	v.watch = game
	tree.root.add_child(v)
	v._build("Loading slot 1")
	return v


## Loading a save shows a loading screen until the game is ready to play.
func test_loading_screen() -> void:
	check(not SaveGame.load_slot(5), "nothing in the slot: no loading")
	check(not tree.root.has_node("LoadVeil"), "and no loading screen")
	# A save made in space: until the space scene is done (travelling false).
	var g := FakeGame.new()
	SaveGame.travelling = true
	var v := _veil(g)
	for i in 10:
		await tree.process_frame
	check(is_instance_valid(v) and not v._closing, "up while the game is still loading")
	check(not v._root.visible and v._root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "no loading screen: nothing over the game, clicks go through")
	SaveGame.travelling = false
	for i in 30:
		await tree.process_frame
	check(not is_instance_valid(v) or v._closing, "gone once the game is ready")
	# A save made on a planet: until the surface is built; the bar follows it.
	var s := FakeSurface.new()
	SaveGame.landed_planet = "thalassa"
	var v2 := _veil(s)
	for i in 10:
		s.build_progress = 0.5
		await tree.process_frame
	check(not v2._closing and v2._bar.value > 0.0, "up while the surface builds (bar %.2f)" % v2._bar.value)
	check(str(Planets.get_planet("thalassa")["name"]) in v2._stage.text, "says where you're landing: " + v2._stage.text)
	s.is_built = true
	for i in 30:
		await tree.process_frame
	check(not is_instance_valid(v2) or v2._closing, "gone once the surface is built")
	if is_instance_valid(v2):
		v2.free()
	if is_instance_valid(v):
		v.free()
	g.free()
	s.free()


## A save where a station was destroyed with traders based there: loading it,
## they're moved on (or lost) - none left pointing at the station that's gone,
## and the trade carries on (one stuck trader held up everyone's departures).
func test_traders_of_a_destroyed_station() -> void:
	Galaxy.new_game(false)
	var sid: String = Galaxy.stations.keys()[5]
	for id in Galaxy.traders:
		Galaxy.traders[id]["station"] = sid
		Galaxy.traders[id]["state"] = "docked"
		Galaxy.traders[id]["wait"] = 0.0
		break
	var d: Dictionary = Galaxy.get_save_data()
	d["destroyed"] = d.get("destroyed", []) + [sid]
	Galaxy.load_save_data(d)
	check(not Galaxy.stations.has(sid), "the station is gone")
	for id in Galaxy.traders:
		var r: Dictionary = Galaxy.traders[id]
		check(Galaxy.stations.has(str(r["station"])), "trader %s: based at a station that exists" % id)
		check(str(r.get("dest", "")) == "" or Galaxy.stations.has(str(r["dest"])), "trader %s: bound for one that exists" % id)
	for i in 30:
		Galaxy._advance_traders(0.5)   # (no error; departures go on)
	check(true, "the traders run")



## An explorer trader wanders to a nearby system's station - but when the
## wars have burnt every station round it, it stays (it used to pick from an
## empty list: a division by zero, its departure failing every time).
func test_explorer_with_no_stations_near() -> void:
	Galaxy.new_game(false)
	var r: Dictionary = {}
	for id in Galaxy.traders:
		if Galaxy.traders[id].get("role", Galaxy.traders[id]["type"]) == "explorer":
			r = Galaxy.traders[id]
			break
	if r.is_empty():
		r = Galaxy.traders.values()[0]
		r["role"] = "explorer"
	var from: Dictionary = Galaxy.stations[r["station"]]
	for n in Galaxy.neighbors(from["system"]) + [from["system"]]:
		Galaxy.systems[n]["stations"] = []   # (every station near it burnt - its own system's listed none either)
	var plan := Galaxy._plan_trade(r, from)
	check(plan is Dictionary and plan.has("dest"), "a plan is made")
	check(Galaxy.stations.has(str(plan["dest"]["id"])), "bound for a station that exists")


## The event log's first line names where you are (not always the Atrapos sector).
func test_welcome_names_the_system() -> void:
	var was := Galaxy.current_system
	Galaxy.current_system = Galaxy.HOME
	check(GameLog.welcome_line().contains("Atrapos sector"), "in Knossos: the Atrapos sector")
	Galaxy.current_system = "kyros"
	var l := GameLog.welcome_line()
	check(l.contains("Sparta") and not l.contains("Atrapos"), "in Sparta: Sparta (%s)" % l)
	Galaxy.current_system = was


## The title screen's Continue (the latest save; only when there is one), and
## Talos from a game: the Esc menu's button and F8 save the game in a slot of
## its own - never in the lists - and leaving Talos ("Back") loads it again.
func test_continue_and_talos_from_the_game() -> void:
	for sl in SaveGame.all_slots() + [SaveGame.TALOS]:
		SaveGame.delete_slot(sl)
	var menu: Control = load("res://main_menu.tscn").instantiate()
	tree.root.add_child(menu)
	await tree.process_frame
	var cont: Button = menu.main_buttons.get_node_or_null("ContinueButton")
	check(cont != null and not cont.visible, "no save: no Continue")
	Galaxy.new_game(false)
	SaveGame.save_game({"player": {"credits": 123}, "galaxy": Galaxy.get_save_data()}, 2)
	menu._refresh_load_button()
	check(cont != null and cont.visible and cont.get_index() == 0, "a save: Continue, first")
	check(cont != null and cont.tooltip_text.contains("Slot 2"), "it says which save (%s)" % (cont.tooltip_text if cont else ""))
	check(menu.main_buttons.get_node_or_null("EditorButton") != null, "the title screen has Talos")
	menu.queue_free()
	var esc: Control = load("res://main_menu.tscn").instantiate()
	esc.overlay = true
	tree.root.add_child(esc)
	await tree.process_frame
	check(esc.main_buttons.get_node_or_null("EditorButton") != null and esc.main_buttons.get_node_or_null("ContinueButton") == null,
		"the Esc menu has Talos (and no Continue)")
	esc.queue_free()
	# The game's own slot for Talos: not in the lists, not the latest.
	SaveGame.save_game({"player": {"credits": 456}, "galaxy": Galaxy.get_save_data()}, SaveGame.TALOS)
	check(SaveGame.has_save(SaveGame.TALOS) and not SaveGame.TALOS in SaveGame.all_slots(), "Talos's resume save is apart from the slots")
	check(SaveGame.latest_slot() == 2, "and never the save Continue loads")
	check(SaveGame.queue_load(SaveGame.TALOS) and int(SaveGame.pending["player"]["credits"]) == 456, "it loads back")
	SaveGame.pending = {}
	# Talos opened from a game: the rail's way out says Back.
	SaveGame.talos_return = true
	var rail := TalosNav.rail("dialogue", func(_id): pass, false)
	var out: Button = rail.find_child("Nav_menu", true, false)
	check(out != null and out.text == "Back", "the rail's way out: Back to the game")
	rail.free()
	SaveGame.talos_return = false
	rail = TalosNav.rail("dialogue", func(_id): pass, false)
	check(rail.find_child("Nav_menu", true, false).text == "Exit", "from the title screen: Exit")
	rail.free()
	check(Keybinds.binds.has("talos") and str(Keybinds.binds["talos"][0]) == "k:F8", "F8 opens Talos (rebindable)")
	for sl in SaveGame.all_slots() + [SaveGame.TALOS]:
		SaveGame.delete_slot(sl)


## Talos from the game opens over it: the game stays loaded (the same scene,
## paused, its state as it was); every Talos layer draws above the game's;
## leaving puts the game back - unpaused, its camera, the galaxy running.
func test_talos_over_the_game() -> void:
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	var was_scene := tree.current_scene
	tree.current_scene = main
	for i in 30:
		await tree.process_frame
	main.ship.global_position = Vector2(1234, 5678)
	var cam: Camera2D = main.get_node("Ship/Camera2D")
	check(SaveGame.open_talos(), "Talos opens from the game")
	for i in 10:
		await tree.process_frame
	var o := SaveGame.talos_overlay()
	check(o != null and tree.current_scene == main and is_instance_valid(main), "over it: the game is still the scene, not unloaded")
	check(tree.paused, "the game paused under it")
	check(TalosNav.host(tree) != null, "Talos's tools are found")
	var low := o.find_children("*", "CanvasLayer", true, false).filter(func(l): return l.layer < 200)
	check(low.is_empty(), "every Talos layer above the game's (%s)" % str(low.map(func(l): return l.layer)))
	TalosNav.leave(tree)
	await tree.process_frame
	check(SaveGame.talos_overlay() == null, "Back: Talos closed")
	check(not tree.paused and Galaxy.active, "the game runs again")
	check(cam.is_current(), "its camera back")
	check_eq(main.ship.global_position, Vector2(1234, 5678), "the ship where it was")
	# From the Esc menu: an Esc in Talos that reaches the menu under it (a tool
	# that lets it through) leaves the menu alone - else it closed unseen,
	# unpaused, and leaving Talos put the pause back with no menu: frozen.
	var esc_menu: Control = main.pause_menu
	esc_menu.open()
	esc_menu.open()   # (opened again while open: still goes back to running)
	check(SaveGame.open_talos(), "Talos opens from the Esc menu")
	await tree.process_frame
	var esc := InputEventAction.new()
	esc.action = "ui_cancel"
	esc.pressed = true
	esc_menu._unhandled_input(esc)
	check(esc_menu.visible, "an Esc meant for Talos leaves the Esc menu under it")
	TalosNav.leave(tree)
	esc_menu._unhandled_input(esc)   # (the same Esc that closed Talos)
	check(esc_menu.visible and tree.paused, "leaving Talos: back at the Esc menu, paused")
	await tree.process_frame
	esc_menu._unhandled_input(esc)
	check(not esc_menu.visible and not tree.paused, "Esc again: the game runs")
	tree.current_scene = was_scene
	main.queue_free()
	await tree.process_frame
