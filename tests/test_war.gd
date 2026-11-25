extends TestCase
## War fleets (Fleets), damaged / destroyed stations, the crisis missions and
## the trade routes you know of.


func setup() -> void:
	Galaxy.new_game(false)


func _war(a: String, b: String) -> void:
	Galaxy._set_relation(a, b, -90.0)


func test_fleets_staffed() -> void:
	check(not Fleets.fleets.is_empty(), "fleets at the start")
	for f in Fleets.fleets.values():
		check(f["size"] >= Fleets.MIN_SIZE and f["size"] <= Fleets.MAX_SIZE, "3 to 12 ships (%d)" % f["size"])
		check(f["empire"] in Galaxy.MAJOR, "an empire's fleet")
	for e in Galaxy.MAJOR:
		check(Fleets.fleets.values().any(func(f): return f["empire"] == e and f["mission"] == "defend"), "%s defends its systems" % e)


func test_invasion_burns_destroys_and_captures() -> void:
	Galaxy.current_system = "atrapos"
	# Sparta invades a Minoan system next to it (Zakros: delos).
	_war("sparta", "minoa")
	var target := "delos"
	for f in Fleets.fleets.values().duplicate():
		if f["system"] == target:
			Fleets.fleets.erase(f["id"])   # (no defenders: a clean siege)
	var f: Dictionary = Fleets._new_fleet("sparta", "invade", target, 12, [])
	f["target"] = target
	var minoan: Array = Galaxy.system(target)["stations"].filter(func(s): return Galaxy.station_owner(s) == "minoa")
	check(not minoan.is_empty(), "Minoan stations to besiege")
	check(Fleets.besieged(minoan[0]), "besieged")
	var first: String = minoan[0]
	var burned := false
	for i in 200:
		Fleets._fight()
		if Galaxy.stations.has(first) and Galaxy.station_health(first) < Galaxy.DAMAGED:
			burned = true
		if Galaxy.owner_of(target) == "sparta":
			break
	check(burned, "a station burned (below %d)" % Galaxy.DAMAGED)
	check(not Galaxy.stations.has(first), "and then was destroyed")
	check(first in Galaxy.destroyed_stations, "for good")
	check_eq(Galaxy.owner_of(target), "sparta", "the system fell to the invader")
	# Saved and loaded: the stations stay gone, the fleet stays.
	var d := Galaxy.get_save_data()
	Galaxy.load_save_data(d)
	check(not Galaxy.stations.has(first), "still gone after loading")
	check(Fleets.fleets.has(f["id"]), "the fleet kept")


func test_crisis_missions() -> void:
	Galaxy.current_system = "atrapos"
	var sid: String = Galaxy.system("atrapos")["stations"][0]
	var rec: Dictionary = Galaxy.stations[sid]
	var ms: Node = load("res://scripts/sim/missions.gd").new()
	tree.root.add_child(ms)
	var normal: Array = ms.offers_for(rec["name"], "minoa")
	check(not normal.any(func(m): return m["type"] in ["repair", "defend"]), "a healthy station: the usual jobs")
	Galaxy.damage_station(sid, 70.0)
	_war("sparta", "minoa")
	Fleets._new_fleet("sparta", "invade", "atrapos", 6, [])["target"] = "atrapos"
	var crisis: Array = ms.offers_for(rec["name"], "minoa")
	check(crisis.all(func(m): return m["type"] in ["repair", "defend"]), "a burning station: only repair and defence")
	check(crisis.any(func(m): return m["type"] == "repair"), "repairs")
	check(crisis.any(func(m): return m["type"] == "defend" and m["target_empire"] == "sparta"), "defence against the besiegers")
	# A repair delivered mends the station and raises your standing.
	var data: Node = load("res://scripts/sim/player_data.gd").new()
	tree.root.add_child(data)
	var job: Dictionary = crisis.filter(func(m): return m["type"] == "repair")[0]
	data.add_item(job["item"], job["count"])
	var before := Galaxy.station_health(sid)
	var rep: float = Galaxy.reputation["minoa"]
	ms.active.append(job)
	check(ms.can_turn_in(job, rec["name"]), "turn it in here")
	data.add_to_group("player_data")
	ms.turn_in(job)
	check(Galaxy.station_health(sid) > before, "mended (%.0f -> %.0f)" % [before, Galaxy.station_health(sid)])
	check(Galaxy.reputation["minoa"] > rep, "they like you more")
	# A defence job counts the besiegers' ships destroyed here.
	var dj: Dictionary = crisis.filter(func(m): return m["type"] == "defend")[0]
	ms.active.append(dj)
	ms.on_enemy_killed("traced_sparta_lambda", "sparta")
	check_eq(dj["progress"], 1, "a Spartan warship destroyed: counted")
	ms.on_enemy_killed("traced_athens_noctua", "athens")
	check_eq(dj["progress"], 1, "another empire's: not")
	ms.queue_free()
	data.queue_free()
	await tree.process_frame


func test_trade_routes_you_know() -> void:
	check(TradeRoutes.galaxy_routes("", 2, 10).is_empty(), "nothing known: no runs")
	var here: Array = Galaxy.system("atrapos")["stations"]
	for sid in here:
		Galaxy.visit_station(sid)
	for sid in TradeRoutes.stations_of(TradeRoutes.reach("atrapos", 2).keys()):
		Galaxy.see_station(sid)
	var runs := TradeRoutes.galaxy_routes("", 2, 10)
	for r in runs:
		check(Galaxy.knows_market(r["from"]), "starts at a market you know")
		check(Galaxy.knows_station(r["to"]), "ends at a station you've found")
	# Friendly with an empire: all of its markets.
	var ion: Array = Galaxy.stations.keys().filter(func(s): return Galaxy.station_owner(s) == "ionia")
	check(not Galaxy.knows_market(ion[0]), "an Ionian market unknown")
	Galaxy.change_reputation("ionia", 50.0 / Galaxy.REP_GAIN)   # (to Friendly: gains count REP_GAIN of themselves)
	check(Galaxy.knows_market(ion[0]), "Friendly with Ionia: its markets known")


## Reputation grows ten times slower than it's given (REP_GAIN); it's lost in full.
func test_reputation_grows_slowly() -> void:
	Galaxy.new_game(false)
	Galaxy.reputation["athens"] = 0.0
	Galaxy.change_reputation("athens", 10.0)
	check(is_equal_approx(Galaxy.reputation["athens"], 1.0), "a gain of 10 counts 1 (%.2f)" % Galaxy.reputation["athens"])
	Galaxy.change_reputation("athens", -5.0)
	check(is_equal_approx(Galaxy.reputation["athens"], -4.0), "a loss counts in full (%.2f)" % Galaxy.reputation["athens"])
