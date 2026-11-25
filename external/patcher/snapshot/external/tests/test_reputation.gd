extends TestCase
## Independents, who runs which station (the occupying empire keeps the
## majority; independent free ports, allies' outposts, forward bases), and
## your reputation (tiers, how it moves, what it does). The old pledge /
## merits / ranks layer is gone.


func test_independents() -> void:
	Galaxy.new_game(false)
	check(Galaxy.EMPIRES.has("independent"), "an Independents faction")
	check(not "independent" in Galaxy.MAJOR, "not one of the powers")
	for e in Galaxy.MAJOR:
		check(not Galaxy.at_war("independent", e), "independents are at war with no empire (%s)" % e)
	check(Galaxy.at_war("independent", "pirates"), "the Sea Peoples prey on them all the same")
	var indie := Galaxy.stations.keys().filter(func(s): return Galaxy.station_owner(s) == "independent")
	check(indie.size() >= 3, "independent stations in the galaxy (%d)" % indie.size())
	for sid in indie:
		check_eq(Galaxy.station_presence(sid), "independent", "an independent port")
	check(not "pledge" in Galaxy, "no pledge any more")
	check(not "merits" in Galaxy, "no merits any more")


func test_majority_and_guests() -> void:
	Galaxy.new_game(false)
	for id in Galaxy.systems:
		var sys: Dictionary = Galaxy.systems[id]
		var all: Array = sys["stations"]
		var own := all.filter(func(s): return Galaxy.station_owner(s) == sys["owner"]).size()
		check(own > all.size() - own, "%s: the owner runs most stations (%d of %d)" % [sys["name"], own, all.size()])
	# An ally next door may open an outpost; an enemy at war a forward base.
	var target := "delos"   # (Minoan, next to Sparta's and Mycenae's)
	var o := Galaxy.owner_of(target)
	var before: int = Galaxy.systems[target]["stations"].size()
	Galaxy._set_relation("sparta", o, -80.0)
	for i in 400:
		Galaxy._rng.seed = i
		Galaxy._guests_tick()
		if Galaxy.systems[target]["stations"].size() > before:
			break
	var added: bool = Galaxy.systems[target]["stations"].size() > before
	check(added, "a newcomer station in %s" % target)
	if added:
		var sid: String = Galaxy.systems[target]["stations"][-1]
		var e := Galaxy.station_owner(sid)
		check(e != o, "a guest of another empire (%s)" % e)
		check(Galaxy.station_presence(sid) in ["forward", "outpost"], "an outpost or a forward base")
		var all: Array = Galaxy.systems[target]["stations"]
		var own := all.filter(func(s): return Galaxy.station_owner(s) == o).size()
		check(own > all.size() - own, "the owner still runs most")
		# Saved and loaded: it's still there, still theirs.
		var d := Galaxy.get_save_data()
		Galaxy.load_save_data(d)
		check(Galaxy.stations.has(sid) and Galaxy.station_owner(sid) == e, "kept in the save")
	# A conquered system's stations change hands.
	Galaxy._transfer(target, o, "sparta")
	Galaxy.systems[target]["owner"] = "sparta"
	check(Galaxy.systems[target]["stations"].all(func(s): return Galaxy.station_owner(s) != o), "the old owner's stations captured")


func test_reputation_tiers() -> void:
	Galaxy.new_game(false)
	check_eq(Galaxy.standing("athens"), "Neutral", "a fresh start: Neutral")
	Galaxy.reputation["athens"] = 45.0
	check_eq(Galaxy.standing("athens"), "Friendly", "45: Friendly")
	Galaxy.reputation["athens"] = 75.0
	check_eq(Galaxy.standing("athens"), "Allied", "75: Allied")
	Galaxy.reputation["athens"] = -55.0
	check_eq(Galaxy.standing("athens"), "Hostile", "-55: Hostile")
	check(Galaxy.is_hostile_to_player("athens"), "Hostile is hostile")
	Galaxy.reputation["athens"] = -30.0
	check(not Galaxy.is_hostile_to_player("athens"), "Unfriendly isn't (yet)")
	# Slow: several ships destroyed before an empire turns on you.
	Galaxy.reputation["athens"] = 0.0
	var kills := 0
	while not Galaxy.is_hostile_to_player("athens") and kills < 50:
		Galaxy.change_reputation("athens", Galaxy.REP_PROVOKE + Galaxy.REP_KILL)
		kills += 1
	check(kills >= 5, "it takes %d ships to make an enemy (5 or more)" % kills)
	# A bad name fades.
	Galaxy.reputation["athens"] = -20.0
	Galaxy._recover_reputation(10.0)
	check(Galaxy.reputation["athens"] > -20.0 and Galaxy.reputation["athens"] <= 0.0, "fades toward 0")
	# Trading raises it.
	var sid: String = Galaxy.systems["nyx"]["stations"][0]
	var e := Galaxy.station_owner(sid)
	Galaxy.reputation[e] = 0.0
	var data: Node = load("res://scripts/player_data.gd").new()
	tree.root.add_child(data)
	data.add_credits(20000)
	Galaxy.player_buy(sid, "food", 40, data)
	check(Galaxy.reputation[e] > 0.0, "buying at their station: they like you more (%.2f)" % Galaxy.reputation[e])
	# Prices follow standing.
	Galaxy.reputation[e] = 0.0
	var neutral := Galaxy.buy_price(sid, "electronics")
	Galaxy.reputation[e] = 80.0
	check(Galaxy.buy_price(sid, "electronics") < neutral, "allies buy cheaper")
	Galaxy.reputation[e] = -40.0
	check(Galaxy.buy_price(sid, "electronics") > neutral, "the unfriendly pay more")
	data.queue_free()
	await tree.process_frame


func test_sprites_follow_the_owner() -> void:
	Galaxy.new_game(false)
	# Stations: no design shared between two owners; every station in its owner's.
	var seen := {}
	for e in StationArt.BY_EMPIRE:
		for d in StationArt.BY_EMPIRE[e]:
			check(not seen.has(d), "station design %s only %s's (also %s's)" % [d, e, seen.get(d, "")])
			seen[d] = e
			check(ProcArt.has_sprite("station_" + d), "station_%s has a sprite" % d)
	for sid in Galaxy.stations:
		var e := Galaxy.station_owner(sid)
		check(StationArt.design_for(e, sid) in StationArt.BY_EMPIRE[e], "%s: a %s design" % [Galaxy.stations[sid]["name"], e])
	# Ships: a design flown by an empire is that empire's own.
	for e in Galaxy.MAJOR + ["independent", "pirates"]:
		for role in ["trader", "miner", "explorer", "fighter", "gunship"]:
			var id := ShipDesigns.pick(e, [role])
			if id != "" and not (e == "pirates" and role in ["trader", "miner", "explorer"]):   # (raiders have no civilians)
				check_eq(ShipDesigns.owner_of(id), e, "%s %s: %s" % [e, role, id])
	for id in Galaxy.traders:
		var r: Dictionary = Galaxy.traders[id]
		check_eq(ShipDesigns.owner_of(r["type"]), r["empire"], "trader %s (%s) in its empire's design" % [r["name"], r["type"]])
	check(ProcArt.has_sprite("ship_traced_drifter") and ProcArt.has_sprite("ship_traced_prospector"), "the independents' haulers have sprites")


func test_home_stations_in_their_owners_colour() -> void:
	Galaxy.new_game(false)
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	await tree.process_frame
	for st in tree.get_nodes_in_group("stations"):
		check_eq(st.accent, Galaxy.empire_color(st.empire), "%s glows in its owner's colour" % st.station_name)
		check(st.design() in StationArt.BY_EMPIRE[st.empire], "%s in its owner's design" % st.station_name)
	main.queue_free()
	await tree.process_frame
