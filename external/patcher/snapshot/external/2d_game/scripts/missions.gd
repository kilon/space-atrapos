extends Node
## Missions (the stations' jobs). Every station offers MISSIONS_PER_STATION;
## the player can run up to MAX_ACTIVE at once.
##   bounty  - destroy N hostile ships of any kind     (completes by itself)
##   hunt    - destroy N ships of one class            (completes by itself)
##   courier - dock at another station                 (completes on docking there)
##   supply  - bring N trade goods to another station  (handed over on docking there)
##   salvage - bring N salvage / ore to this station   (turn it in here)
##   survey  - fly to an uncharted point and scan it   (completes on arriving)
##   repair  - bring repair materials to this damaged station (turn it in here;
##             mends the station - Galaxy.repair_station)
##   defend  - destroy N ships of the empire besieging this station's system
## War missions (empires with a war on, or an invasion coming - _fill_war):
##   protect     - an invasion is coming for a system of theirs: destroy N of
##                 the invader's warships there
##   strike      - take N% off an enemy station's condition (or destroy it)
##   join        - fly with one of their fleets (Fleets) for N seconds
##   attack_fleet - destroy N ships of an enemy fleet, wherever it goes
## A severely damaged station (Galaxy.DAMAGED) offers only repair and defend
## missions (crisis_offers) until it's mended.
## Each mission has a tier (TIERS): the better ones need a good reputation
## with the station's empire (Galaxy.reputation) and pay more; ones you
## aren't trusted with yet show greyed out (available() false). Finishing a
## mission raises your reputation with that empire (more for higher tiers).

signal changed
signal completed(mission: Dictionary)

const MAX_ACTIVE := 5
const MISSIONS_PER_STATION := 8
## Tiers: name, the reputation needed, the reward multiplier, the reputation earned.
## The thresholds are the standing tiers' (Galaxy.REP_TIERS): Routine from
## Unfriendly, Trusted from Cordial, Honoured from Friendly, Hero when Allied.
const TIERS := [
	{"name": "Routine", "rep": -49.0, "pay": 1.0, "earn": 1.0},
	{"name": "Trusted", "rep": 15.0, "pay": 1.5, "earn": 2.0},
	{"name": "Honoured", "rep": 40.0, "pay": 2.2, "earn": 3.0},
	{"name": "Hero", "rep": 70.0, "pay": 3.2, "earn": 4.0},
]
## How likely each tier is among a station's offers.
const TIER_ODDS := [0.4, 0.3, 0.2, 0.1]
const SURVEY_RANGE := 700.0
## Flying with a fleet (join missions): within this of one of its ships.
const JOIN_RANGE := 1600.0

var offers := {}   # station name -> Array of mission dicts
var active := []   # accepted missions
var _next_id := 1
var _check_t := 0.0


func _ready() -> void:
	add_to_group("missions")


func _data() -> Node:
	return get_tree().get_first_node_in_group("player_data")


## A station's offers (made the first time it's asked; `empire`: who runs it).
## A burning station (in this system, below Galaxy.DAMAGED) gives only its
## crisis jobs: repairs, and defence while it's besieged.
## How dangerous each kind of job is, 0 (safe) to 1 (deadly).
const DANGER := {"courier": 0.0, "survey": 0.0, "supply": 0.3, "salvage": 0.3, "repair": 0.3,
	"bounty": 0.7, "join": 0.7, "defend": 0.7, "hunt": 1.0, "protect": 1.0, "strike": 1.0, "attack_fleet": 1.0}
## The most a job's pay is raised: the hardest (a Hero-tier hunt, strike or raid).
const PAY_MAX := 10.0

## A job's difficulty, 0..1: its tier (Routine ... Hero) counts most, then how
## dangerous its kind is.
static func difficulty(m: Dictionary) -> float:
	var tier := clampf(float(m.get("tier", 0)) / 3.0, 0.0, 1.0)
	return 0.6 * tier + 0.4 * float(DANGER.get(str(m.get("type", "")), 0.5))


## What a job's base reward (worked out by each kind of job from what it asks:
## goods' values, distances, enemies) is multiplied by: 1 for the easiest up
## to PAY_MAX for the hardest.
static func pay_mult(m: Dictionary) -> float:
	return 1.0 + (PAY_MAX - 1.0) * difficulty(m)


## Raises a job's pay by its difficulty - once, as it's made (or as an older
## save's jobs load).
func _paid(m: Dictionary) -> Dictionary:
	if not m.get("pay_raised", false):
		m["reward"] = roundi(int(m["reward"]) * pay_mult(m))
		m["pay_raised"] = true
	return m


func offers_for(station_name: String, empire := "") -> Array:
	var rec := Galaxy.station_by_name(Galaxy.current_system, station_name)
	if not rec.is_empty() and Galaxy.station_health(rec["id"]) < Galaxy.DAMAGED:
		return crisis_offers(rec, empire)
	if not offers.has(station_name):
		offers[station_name] = []
		for i in MISSIONS_PER_STATION:
			offers[station_name].append(_paid(_generate(station_name, empire)))
	return offers[station_name]


## A damaged station's jobs: three repair deliveries and a defence job against
## each empire besieging its system (kept while they apply).
func crisis_offers(rec: Dictionary, empire: String) -> Array:
	var key: String = rec["name"] + "#crisis"
	var foes: Array = Fleets.besiegers(rec["system"]).filter(func(e): return Galaxy.at_war(e, empire))
	var list: Array = offers.get(key, []).filter(func(m): return m["type"] == "repair" or m.get("target_empire", "") in foes)
	while list.filter(func(m): return m["type"] == "repair").size() < 3:
		list.append(_paid(_repair_job(rec, empire)))
	for e in foes:
		if not list.any(func(m): return m["type"] == "defend" and m["target_empire"] == e):
			list.append(_paid(_defend_job(rec, empire, e)))
	offers[key] = list
	return list


func _repair_job(rec: Dictionary, empire: String) -> Dictionary:
	var pick: Array = [["machinery", 4, 8], ["iron_ore", 10, 20], ["titanium_ore", 6, 12], ["energy_cell", 4, 8], ["electronics", 3, 6]].pick_random()
	var n := randi_range(pick[1], pick[2])
	var m := {"id": _next_id, "giver": rec["name"], "station_id": rec["id"], "progress": 0, "count": n, "cores": 0, "empire": empire,
		"tier": 0, "min_rep": -49.0, "type": "repair", "item": pick[0],
		"repair": 6.0 + n * 1.2,
		"title": "Repairs: %s" % Items.display_name(pick[0]),
		"reward": int(Items.ITEMS[pick[0]]["value"] * n * 1.5) + 60}
	m["desc"] = "%s is burning. Bring %d %s for the repair crews (mends %d%% of the station)." % [rec["name"], n, Items.display_name(pick[0]), int(m["repair"])]
	_next_id += 1
	return m


func _defend_job(rec: Dictionary, empire: String, foe: String) -> Dictionary:
	var n := randi_range(3, 6)
	var m := {"id": _next_id, "giver": rec["name"], "station_id": rec["id"], "progress": 0, "count": n, "cores": 0, "empire": empire,
		"tier": 0, "min_rep": -49.0, "type": "defend", "target_empire": foe, "system": rec["system"],
		"title": "Defend %s" % rec["name"],
		"reward": n * 260 + 100}
	m["desc"] = "The %s is besieging us. Destroy %d of its warships in this system." % [Galaxy.empire_name(foe), n]
	_next_id += 1
	return m


## The empire trusts you enough to give you this one.
func available(m: Dictionary) -> bool:
	var e: String = m.get("empire", "")
	if e == "":
		return true
	return float(Galaxy.reputation.get(e, 0.0)) >= float(m.get("min_rep", -100.0))


## What it takes, for a mission you can't take yet.
func required_text(m: Dictionary) -> String:
	var t: Dictionary = TIERS[int(m.get("tier", 0))]
	return "%s mission: needs reputation %d with the %s (yours: %d)" % [t["name"], int(t["rep"]),
		Galaxy.empire_name(m.get("empire", "")), int(Galaxy.reputation.get(m.get("empire", ""), 0.0))]


func accept(m: Dictionary) -> bool:
	if active.size() >= MAX_ACTIVE or not available(m):
		return false
	var list: Array = offers_for(m["giver"], m.get("empire", ""))
	list.erase(m)
	if not m["type"] in ["repair", "defend"]:
		list.append(_paid(_generate(m["giver"], m.get("empire", ""))))
	active.append(m)
	GameLog.post("Mission accepted: %s" % m["title"], "mission")
	changed.emit()
	return true


func abandon(m: Dictionary) -> void:
	active.erase(m)
	GameLog.post("Mission abandoned: %s" % m["title"], "mission")
	changed.emit()


## Enemy ship types wanted by active hunt missions (spawner favours these).
func wanted_types() -> Array:
	var out := []
	for m in active:
		if m["type"] == "hunt":
			out.append(m["target_type"])
	return out


func on_enemy_killed(type_id: String, empire := "", fleet_id := "") -> void:
	for m in active.duplicate():
		var defend: bool = m["type"] in ["defend", "protect"] and m["target_empire"] == empire and m.get("system", "") == Galaxy.current_system
		var fleet: bool = m["type"] == "attack_fleet" and fleet_id != "" and m.get("fleet", "") == fleet_id
		if defend or fleet or (m["type"] == "bounty" and empire == "pirates") or (m["type"] == "hunt" and m["target_type"] == type_id):
			m["progress"] += 1
			if m["progress"] >= m["count"]:
				_complete(m)
	changed.emit()


func on_docked(station_name: String) -> void:
	for m in active.duplicate():
		if m["type"] == "courier" and m["target_station"] == station_name:
			_complete(m)
		elif m["type"] == "supply" and m["target_station"] == station_name and _data().count(m["item"]) >= m["count"]:
			_data().remove_item(m["item"], m["count"])
			_complete(m)


## A strike mission's station hit by you: `pct` of its condition off.
func on_station_hit(station_id: String, pct: float) -> void:
	for m in active.duplicate():
		if m["type"] == "strike" and m.get("station_id", "") == station_id:
			m["progress"] = minf(float(m["count"]), float(m["progress"]) + pct)
			if float(m["progress"]) >= float(m["count"]) - 0.01 or not Galaxy.stations.has(station_id):
				_complete(m)
			changed.emit()


## Survey missions: arriving at the point scans it. Fleet missions: flying
## with the fleet counts; a fleet that's gone ends its missions.
func _process(delta: float) -> void:
	_check_t -= delta
	if _check_t > 0.0:
		return
	_check_t = 0.5
	var ship := get_tree().get_first_node_in_group("player") as Node2D
	if ship == null:
		return
	for m in active.duplicate():
		if m["type"] == "survey" and m.get("system", "") == Galaxy.current_system \
				and ship.global_position.distance_to(Vector2(m["pos"][0], m["pos"][1])) < SURVEY_RANGE:
			_complete(m)
		elif m["type"] in ["join", "attack_fleet"] and not Fleets.fleets.has(m.get("fleet", "")):
			if int(m["progress"]) > 0:
				GameLog.post("%s: the fleet is gone - what you did counts." % m["title"], "mission")
				_complete(m)
			else:
				active.erase(m)
				GameLog.post("Mission over: %s - the fleet is gone." % m["title"], "mission")
				changed.emit()
		elif m["type"] == "join" and Fleets.fleets[m["fleet"]]["system"] == Galaxy.current_system:
			var near := false
			for n in get_tree().get_nodes_in_group("neutrals") + get_tree().get_nodes_in_group("enemies"):
				if n.get("fleet_id") == m["fleet"] and n.is_alive() and n.global_position.distance_to(ship.global_position) < JOIN_RANGE:
					near = true
					break
			if near:
				m["progress"] = int(m["progress"]) + 1   # (half-seconds)
				if int(m["progress"]) >= int(m["count"]) * 2:
					_complete(m)
				changed.emit()
		elif m["type"] == "strike" and not Galaxy.stations.has(m.get("station_id", "")):
			_complete(m)   # (destroyed - by you or by others: the job's done)


func can_turn_in(m: Dictionary, station_name: String) -> bool:
	return m["type"] in ["salvage", "repair"] and m["giver"] == station_name \
			and _data().count(m["item"]) >= m["count"]


func turn_in(m: Dictionary) -> void:
	if _data().remove_item(m["item"], m["count"]):
		if m["type"] == "repair":
			Galaxy.repair_station(m.get("station_id", ""), float(m.get("repair", 10.0)))
			GameLog.post("%s: repairs under way (+%d%%)." % [m["giver"], int(m.get("repair", 10.0))], "good")
		_complete(m)


func progress_text(m: Dictionary) -> String:
	match m["type"]:
		"bounty", "hunt", "defend":
			return "%d / %d destroyed" % [m["progress"], m["count"]]
		"protect":
			return "%d / %d %s warships destroyed  ·  in %s" % [m["progress"], m["count"], Galaxy.EMPIRES[m["target_empire"]]["short"],
				Galaxy.system(m["system"]).get("name", "?")]
		"attack_fleet", "join":
			var f: Dictionary = Fleets.fleets.get(m.get("fleet", ""), {})
			var where: String = Galaxy.system(f.get("system", "")).get("name", "?") if not f.is_empty() else "gone"
			if m["type"] == "join":
				return "%d / %d s with the fleet  ·  it's in %s" % [int(m["progress"]) / 2, m["count"], where]
			return "%d / %d of its ships destroyed  ·  the fleet is in %s" % [m["progress"], m["count"], where]
		"strike":
			return "%d%% / %d%% off %s  ·  in %s" % [int(m["progress"]), m["count"], m["target_station"], Galaxy.system(m["system"]).get("name", "?")]
		"repair":
			return "%d / %d %s  ·  bring to %s" % [mini(_data().count(m["item"]), m["count"]), m["count"],
				Items.display_name(m["item"]), m["giver"]]
		"courier":
			return "Dock at %s" % m["target_station"]
		"supply":
			return "%d / %d %s  ·  dock at %s" % [mini(_data().count(m["item"]), m["count"]), m["count"],
				Items.display_name(m["item"]), m["target_station"]]
		"salvage":
			return "%d / %d %s  ·  turn in at %s" % [
				mini(_data().count(m["item"]), m["count"]), m["count"],
				Items.display_name(m["item"]), m["giver"]]
		"survey":
			var ship := get_tree().get_first_node_in_group("player") as Node2D
			var p := Vector2(m["pos"][0], m["pos"][1])
			if ship and m.get("system", "") == Galaxy.current_system:
				return "Fly to the survey point (%.1fk away, on your map)" % (ship.global_position.distance_to(p) / 1000.0)
			return "Fly to the survey point in %s" % Galaxy.system(m.get("system", "")).get("name", "?")
	return ""


func reward_text(m: Dictionary) -> String:
	var t := "%d dr" % m["reward"]
	if m.get("cores", 0) > 0:
		t += " + %d Data Core" % m["cores"]
	return t


## Survey points of the active missions in this system (for the maps): [{pos, name}].
func markers() -> Array:
	var out := []
	for m in active:
		if m["type"] == "survey" and m.get("system", "") == Galaxy.current_system:
			out.append({"pos": Vector2(m["pos"][0], m["pos"][1]), "name": m["title"]})
	return out


func _complete(m: Dictionary) -> void:
	active.erase(m)
	var data := _data()
	data.add_credits(m["reward"])
	if m.get("cores", 0) > 0:
		data.add_item("data_core", m["cores"])
	var e: String = m.get("empire", "")
	if e != "" and e != "pirates":
		Galaxy.change_reputation(e, TIERS[int(m.get("tier", 0))]["earn"])
	GameLog.post("Mission complete: %s  (+%s)" % [m["title"], reward_text(m)], "good")
	completed.emit(m)
	changed.emit()


func _generate(giver: String, empire := "") -> Dictionary:
	# The tier: routine jobs most often, hero jobs rarely.
	var r := randf()
	var tier := 0
	for k in TIER_ODDS.size():
		r -= TIER_ODDS[k]
		if r <= 0.0:
			tier = k
			break
	var td: Dictionary = TIERS[tier]
	var m := {"id": _next_id, "giver": giver, "progress": 0, "count": 1, "cores": 0, "empire": empire,
		"tier": tier, "min_rep": td["rep"] if empire != "" else -100.0}
	_next_id += 1
	var others := []
	var here := Vector2.ZERO
	for st in get_tree().get_nodes_in_group("stations"):
		if st.station_name == giver:
			here = st.global_position
		else:
			others.append(st)
	var hard := 1.0 + tier * 0.5   # higher tiers: more to do
	var kinds := ["bounty", "bounty", "hunt", "salvage", "salvage", "survey"]
	if not others.is_empty():
		kinds += ["courier", "supply", "supply"]
	if empire in Galaxy.MAJOR and randf() < 0.4 and _fill_war(m, empire, hard):
		m["reward"] = int(m["reward"] * float(td["pay"]))
		return m
	match kinds.pick_random():
		"bounty":
			m["type"] = "bounty"
			m["count"] = int(randi_range(3, 6) * hard)
			m["title"] = ["Pirate Sweep", "Clear the Lanes", "Raider Patrol", "Convoy Cover"].pick_random()
			m["desc"] = "Raiders are harassing our traffic. Destroy %d hostile ships of any kind." % m["count"]
			m["reward"] = m["count"] * 140 + randi_range(0, 4) * 10
		"hunt":
			# (raiders fly the Sea Peoples' own designs: the hunted class is one of those)
			var type_id: String = EnemyTypes.ids().filter(func(id): return ShipDesigns.owner_of(id) == "pirates").pick_random()
			var t := EnemyTypes.get_type(type_id)
			m["type"] = "hunt"
			m["target_type"] = type_id
			m["count"] = 1 if t["hull"] >= 120.0 else randi_range(1, 2) + tier / 2
			m["title"] = "Hunt: %s" % t["name"]
			m["desc"] = "A %s has been attacking convoys. Track it down and destroy %d." % [t["name"], m["count"]]
			m["reward"] = int(t["hull"] * 2.5) * m["count"] + 80
			m["cores"] = 1 if t["hull"] >= 150.0 or tier >= 3 else 0
		"salvage":
			var pick: Array = [["scrap", 4, 8], ["energy_cell", 3, 5], ["alien_alloy", 2, 3],
					["iron_ore", 6, 12], ["titanium_ore", 4, 8], ["platinum_ore", 2, 3]].pick_random()
			m["type"] = "salvage"
			m["item"] = pick[0]
			m["count"] = int(randi_range(pick[1], pick[2]) * hard)
			var ore: bool = str(pick[0]).ends_with("_ore")
			m["title"] = "Mining Contract" if ore else "Salvage Request"
			m["desc"] = "Our %s need %d %s. Bring them here." % ["smelters" if ore else "workshops", m["count"], Items.display_name(pick[0])]
			m["reward"] = int(Items.ITEMS[pick[0]]["value"] * m["count"] * 2.0) + 40
		"courier":
			var dest: Node2D = others.pick_random()
			var dist := here.distance_to(dest.global_position)
			m["type"] = "courier"
			m["target_station"] = dest.station_name
			m["title"] = ["Courier to %s", "Sealed Dispatch: %s", "Diplomatic Pouch: %s"].pick_random() % dest.station_name
			m["desc"] = "Deliver a sealed package to %s. Dock there to complete the job." % dest.station_name
			m["reward"] = int(dist / 12.0) + 60
		"supply":
			var dest: Node2D = others.pick_random()
			var item: String = ["food", "water", "medicine", "machinery", "electronics", "fuel"].pick_random()
			m["type"] = "supply"
			m["target_station"] = dest.station_name
			m["item"] = item
			m["count"] = int(randi_range(5, 12) * hard)
			m["title"] = "Supply Run: %s" % Items.display_name(item)
			m["desc"] = "%s is short of %s. Bring them %d (buy them at a market) and dock there." % [dest.station_name, Items.display_name(item).to_lower(), m["count"]]
			m["reward"] = int(Items.ITEMS[item]["value"] * m["count"] * 1.6 + here.distance_to(dest.global_position) / 20.0) + 50
		"survey":
			m["type"] = "survey"
			m["system"] = Galaxy.current_system
			var p := Vector2.ZERO
			for k in 30:   # somewhere you haven't charted yet, if possible
				p = Vector2.from_angle(randf() * TAU) * randf_range(4000.0, Galaxy.FOG_EXTENT * 0.75)
				if not Galaxy.explored_at(p):
					break
			m["pos"] = [p.x, p.y]
			m["title"] = ["Survey: Uncharted Sector", "Sensor Sweep", "Chart the Dark"].pick_random()
			m["desc"] = "Fly to a point we haven't charted (marked on your map) and scan it. Arriving completes the job."
			m["reward"] = int(here.distance_to(p) / 10.0) + 90
	m["reward"] = int(m["reward"] * float(td["pay"]))
	return m


## A war mission for `empire` (into m), if there's a war or an invasion to
## give one: protect a system an invasion is coming for, strike an enemy
## station, join one of its fleets, attack an enemy fleet - within reach of
## here. False: nothing to offer.
func _fill_war(m: Dictionary, empire: String, hard: float) -> bool:
	var here := Galaxy.current_system
	var jumps := func(sys: String) -> int:
		var r := Galaxy.find_route(here, sys)
		return r.size() - 1 if not r.is_empty() else (0 if sys == here else 99)
	var choices := []
	for f in Fleets.fleets.values():
		if f["mission"] == "invade" and Galaxy.at_war(f["empire"], empire) and Galaxy.owner_of(f["target"]) == empire and jumps.call(f["target"]) <= 3:
			choices.append(["protect", f])
		elif Galaxy.at_war(f["empire"], empire) and f["empire"] != "pirates" and jumps.call(f["system"]) <= 3:
			choices.append(["attack_fleet", f])
		elif f["empire"] == empire and jumps.call(f["system"]) <= 3:
			choices.append(["join", f])
	for sid in Galaxy.stations:
		var st: Dictionary = Galaxy.stations[sid]
		var o := Galaxy.station_owner(sid)
		if o in Galaxy.MAJOR and Galaxy.at_war(o, empire) and st["system"] != Galaxy.HOME and jumps.call(st["system"]) <= 2:
			choices.append(["strike", sid])
	if choices.is_empty():
		return false
	var c: Array = choices.pick_random()
	match c[0]:
		"protect":
			var f: Dictionary = c[1]
			m["type"] = "protect"
			m["target_empire"] = f["empire"]
			m["system"] = f["target"]
			m["count"] = int(randi_range(3, 6) * hard)
			m["title"] = "Protect %s" % Galaxy.system(f["target"])["name"]
			m["desc"] = "The %s is coming for %s with an invasion. Be there and destroy %d of its warships." % [Galaxy.empire_name(f["empire"]),
				Galaxy.system(f["target"])["name"], m["count"]]
			m["reward"] = m["count"] * 300 + 150
		"attack_fleet":
			var f: Dictionary = c[1]
			m["type"] = "attack_fleet"
			m["fleet"] = f["id"]
			m["target_empire"] = f["empire"]
			m["count"] = mini(int(f["size"]), int(randi_range(2, 5) * hard))
			m["title"] = "Raid: the %s fleet" % Galaxy.EMPIRES[f["empire"]]["short"]
			m["desc"] = "A %s fleet of %d warships is in %s. Find it - it moves - and destroy %d of its ships." % [Galaxy.EMPIRES[f["empire"]]["short"],
				int(f["size"]), Galaxy.system(f["system"])["name"], m["count"]]
			m["reward"] = m["count"] * 340 + 120
		"join":
			var f: Dictionary = c[1]
			m["type"] = "join"
			m["fleet"] = f["id"]
			m["count"] = 60 + 30 * int(hard - 1.0)
			m["title"] = "Join the %s fleet" % ("invasion" if f["mission"] == "invade" else "defence")
			m["desc"] = "Our %s fleet (%d warships) is in %s. Fly with it - within %d of its ships - for %d seconds, and fight beside it." % [
				"invasion" if f["mission"] == "invade" else "defence", int(f["size"]), Galaxy.system(f["system"])["name"], int(JOIN_RANGE), m["count"]]
			m["reward"] = m["count"] * 6 + 200
		"strike":
			var sid: String = c[1]
			var st: Dictionary = Galaxy.stations[sid]
			m["type"] = "strike"
			m["station_id"] = sid
			m["target_station"] = st["name"]
			m["system"] = st["system"]
			m["count"] = int(randi_range(8, 15) * hard)
			m["title"] = "Strike: %s" % st["name"]
			m["desc"] = "%s in %s serves the %s, our enemy. Take %d%% off its condition (it costs you standing with them)." % [st["name"],
				Galaxy.system(st["system"])["name"], Galaxy.empire_name(Galaxy.station_owner(sid)), m["count"]]
			m["reward"] = m["count"] * 60 + 200
	return true


func get_save_data() -> Dictionary:
	return {"offers": offers, "active": active, "next_id": _next_id}


func load_save_data(data: Dictionary) -> void:
	offers = {}
	var saved_offers: Dictionary = data.get("offers", {})
	for station in saved_offers:
		offers[station] = []
		for m in saved_offers[station]:
			offers[station].append(_paid(_fix_numbers(m)))   # (a save from before: its jobs pay the new rate too)
	active = []
	for m in data.get("active", []):
		active.append(_paid(_fix_numbers(m)))
	_next_id = int(data.get("next_id", 1))
	changed.emit()


## JSON turns ints into floats; restore the integer fields.
static func _fix_numbers(m: Dictionary) -> Dictionary:
	for key in ["id", "progress", "count", "reward", "cores", "tier"]:
		if m.has(key):
			m[key] = int(m[key])
	return m
