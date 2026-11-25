extends TestCase
## The Ionian League: its systems, fleet, stations, theme and portraits.


func setup() -> void:
	Galaxy.new_game(false)


func test_ionian_space() -> void:
	var own := Galaxy.SYSTEMS.keys().filter(func(id): return Galaxy.owner_of(id) == "ionia")
	check_eq(own.size(), Galaxy.EMPIRE_SIZE["ionia"], "Ionian systems")
	for id in own:
		check(not Galaxy.neighbors(id).is_empty(), id + " has gates")
		check(not Galaxy.find_route(Galaxy.HOME, id).is_empty(), "route from home to " + id)
		check(Galaxy.system(id)["stations"].size() >= 2, id + " has stations")
	check(Galaxy.MAJOR.has("ionia"), "Ionia is a major power")
	check(Galaxy.reputation.has("ionia"), "reputation with Ionia")


func test_ionian_fleet_and_stations() -> void:
	var ships := EnemyTypes.all_ids().filter(func(id): return EnemyTypes.get_type(id).get("empire_style", "") == "ionia" and not EnemyTypes.get_type(id).get("capital", false))
	check_eq(ships.size(), 12, "Ionian ship classes")
	for id in ships:
		check(ProcArt.has_sprite("ship_" + id), "traced art for " + id)
	# (and its capital ships, drawn with one of its own hulls)
	for cls in ShipDesigns.CAPITAL_CLASSES:
		var cap: String = "cap_ionia_" + cls
		check(EnemyTypes.has_type(cap) and ProcArt.has_sprite("ship_" + str(EnemyTypes.get_type(cap)["art"])), "an Ionian %s, with art" % cls)
	for i in 10:
		check(EnemyTypes.get_type(ShipDesigns.warship("ionia")).get("empire_style", "") in ["ionia", ""], "Ionian warship pick")
	for role in ["trader", "miner", "explorer"]:
		check(ShipDesigns.pick("ionia", [role]) != "", "Ionia has a " + role)
	check(Shipyard.for_sale("ionia").size() >= 12, "Ionian shipyard")
	for d in StationArt.BY_EMPIRE["ionia"]:
		check(ProcArt.has_sprite("station_" + d), "traced art for station " + d)
	check(StationArt.design_for("ionia", "x").begins_with("ionia_"), "Ionian stations use Ionian designs")


func test_ionian_theme_and_portrait() -> void:
	check(NeonTheme.PALETTES.has("ionia"), "Ionian GUI palette")
	NeonTheme.set_empire("ionia")
	check_eq(NeonTheme.empire, "", "the GUI keeps its one look in Ionian space too")
	NeonTheme.set_empire("")
	var p := Portrait.new().setup("Herakleitos", "ionia")
	check(p != null, "Ionian portrait")
	tree.root.add_child(p)
	await tree.process_frame
	p.queue_free()
