extends TestCase
## The Encyclopedia reveals only what you've discovered (Discovery): a new
## game knows your ship, your laser and your starting items; the rest isn't
## listed until a ship of the class comes near, you dock, pick an item up...
## The discovered set is saved with the player's data.

var _main: Node


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	SaveGame.pending = {}
	SaveGame.travelling = false


## The encyclopedia's entries as the Archive lists them (read afresh: what's discovered now).
func _titles(page: Control) -> Array:
	page._enc_cats = []
	var out := []
	for ch in page.contents("encyclopedia"):
		for p in ch["pages"]:
			out.append(p[1])
	return out


func test_undiscovered_entries_are_hidden() -> void:
	Galaxy.current_system = Galaxy.HOME
	SaveGame.pending = {}
	SaveGame.travelling = false
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 10:
		await tree.process_frame
	var pd: Node = _main.player_data
	pd.discovered = {"item:repair_kit": true, "gear:laser": true}   # (as a new game starts)
	_main.ship_menu.open(_main.ship_menu.ARCHIVE_TAB)
	await tree.process_frame
	var page: Control = _main.ship_menu._pages[_main.ship_menu.ARCHIVE_TAB]
	page.refresh()
	var titles := _titles(page)
	check(titles.has("Atrapos-class Light Fighter"), "your own ship is known")
	check(titles.has("Laser Cannon") or titles.has(Items.WEAPONS["laser"]["name"]), "your laser is known")
	var first_enemy: String = EnemyTypes.ids()[0]
	var enemy_name: String = EnemyTypes.get_type(first_enemy)["name"]
	check(not titles.has(enemy_name), "an enemy class you haven't met is hidden")
	check(not titles.has("Amnissos (ocean world)"), "a planet you haven't flown up to is hidden")
	var lore := QuestData.LORE.size()
	check(titles.count("? ? ?") <= lore, "undiscovered entries aren't listed at all (only the lore's locked ones: %d)" % titles.count("? ? ?"))
	check(titles.size() <= 3 + lore, "a new game's list is short (%d entries)" % titles.size())
	# Met: a ship of the class within range, a scan, and it's listed.
	var e: Node2D = null
	for n in tree.get_nodes_in_group("enemies") + tree.get_nodes_in_group("neutrals"):
		if n.type_id == first_enemy:
			e = n
			break
	if e == null:
		Discovery.mark(tree, "ship:" + first_enemy)
	else:
		e.global_position = _main.ship.global_position + Vector2(400, 0)
		Discovery.scan(_main)
	page.refresh()
	check(_titles(page).has(enemy_name), "once met, the class is in the Encyclopedia")
	# An item picked up, a planet flown up to.
	pd.add_item("scrap", 1)
	var body: Node2D = _main._planet_body("thalassa")
	_main.ship.global_position = body.global_position + Vector2(body.radius + 100.0, 0)
	Discovery.scan(_main)
	page.refresh()
	titles = _titles(page)
	check(titles.has(Items.ITEMS["scrap"]["name"]), "an item you held is known")
	check(titles.has("Amnissos (ocean world)"), "a planet you flew up to is known")
	# Saved and loaded with the player's data.
	var saved: Dictionary = pd.get_save_data()
	check(saved["discovered"].has("planet:thalassa") and saved["discovered"].has("ship:" + first_enemy), "the discoveries are saved")
	pd.discovered = {}
	pd.load_save_data(saved)
	check(pd.discovered.has("planet:thalassa"), "and loaded")
	_main.ship_menu.close()


## On a planet the discoveries live in the surface's state, saved as a list of
## keys: the Field Computer's Encyclopedia reads them (no error), and what you
## pick up there is discovered.
func test_discoveries_on_a_planet() -> void:
	var old := SaveGame.landed_planet
	SaveGame.landed_planet = "thalassa"
	SaveGame.space_state = {"player": {"credits": 150, "items": {"repair_kit": 2}, "equipment": ["laser"], "tech": [],
		"discovered": ["item:repair_kit", "gear:laser", "planet:thalassa"]}, "planets": {}}
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	tree.current_scene = s
	while not s.is_built:
		await tree.process_frame
	check(Discovery.known(tree, "planet:thalassa"), "a discovery saved as a list is read on the planet")
	check(s.state["player"]["discovered"] is Dictionary, "and the list is a dictionary from then on")
	s.field_menu.open(s.field_menu.ARCHIVE_TAB)
	await tree.process_frame
	var page: Control = s.field_menu._pages[s.field_menu.ARCHIVE_TAB]
	check(page.visible and _titles(page).has("Amnissos (ocean world)"), "the Field Computer's Archive: the encyclopedia shows it")
	s._give("scrap", 1)
	check(Discovery.known(tree, "item:scrap"), "an item picked up on the planet is discovered")
	s.field_menu.close()
	s.queue_free()
	await tree.process_frame
	SaveGame.space_state = {}
	SaveGame.landed_planet = old
