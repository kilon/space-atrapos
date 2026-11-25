extends Node
## Autoload "People": everyone in the sector, each a record that lives on -
## names, ages, homes, jobs, money, ships, partners, children, parents,
## friends, the story of their life so far - and where they are now, worked
## out from what they do: a station's staff at their station (on shift or off
## it), a ship's crew aboard their ship - or, while it's docked, at that
## station - a fleet's sailors with their fleet. Nobody appears from nowhere:
## the people you meet in a port work there, live there, or came in on a ship
## that's down on its lift; you can follow one back to their ship and that
## ship on to its next port (Galaxy.traders: their routes), system to system.
##
## Their lives go on a few at a time (a share of them a frame, by time): they
## age; take jobs (a vacancy at their station, a berth on a ship, the navy);
## make friends of the people they work with; pair off with one of them; have
## children, who grow up and find work of their own; save their wages - a
## crew member with enough buys a ship of their own and captains it; at war,
## some enlist and sail with the fleets (Fleets) - and a fleet's ships lost
## are its sailors lost, mourned at home; the old die. Each keeps a short log
## of what happened to them (`log`), which they tell you about.
## The state is saved with the galaxy (Galaxy.get_save_data: "people").

const DAY := 120.0                 # s of play: a day of their lives (shifts turn over three times in it)
const YEAR := 2400.0               # s of play: a year of their ages
const LIFE_TICK := 20.0            # each one's life looked at this often (s)
const ADULT := 17.0
## A station's staff: [job, how many].
const STAFF := [["bartender", 1], ["officer", 2], ["guard", 2], ["dock", 2], ["carrier", 2]]
const CREW_MAX := 3                # a trader's crew besides its captain
const SHIP_PRICE := 9000           # dr: a crew member who has saved this much buys a ship of their own
const WAGE := {"bartender": 40, "officer": 60, "guard": 50, "dock": 40, "carrier": 35, "crew": 55, "captain": 0, "navy": 45, "": 0,
	"farmer": 30, "fisher": 30, "potter": 35, "smith": 45, "weaver": 35, "scribe": 45, "priest": 40, "merchant": 60, "builder": 40}
const JOB_NAMES := {"bartender": "bartender", "officer": "harbour officer", "guard": "port guard", "dock": "dock worker",
	"carrier": "cargo hand", "crew": "crew", "captain": "captain", "navy": "sailor", "": "at home",
	"farmer": "farmer", "fisher": "fisher", "potter": "potter", "smith": "smith", "weaver": "weaver", "scribe": "scribe",
	"priest": "priest", "merchant": "merchant", "builder": "builder"}
## A town's trades.
const TOWN_JOBS := ["farmer", "farmer", "fisher", "potter", "smith", "weaver", "scribe", "priest", "merchant", "builder"]
const GIVEN := ["Alkmene", "Ariston", "Damon", "Eudora", "Glaukos", "Hermione", "Iason", "Kallias", "Lysandra", "Melitta", "Nikias",
	"Phaidra", "Philon", "Rhode", "Sostratos", "Thais", "Timon", "Xanthe", "Zenon", "Kleio", "Myron", "Ione", "Teukros", "Eirene",
	"Aristeia", "Demetrios", "Eurydike", "Hippias", "Kallisto", "Leandros", "Menon", "Nausikaa", "Orestes", "Pherenike", "Stratonike",
	"Thrasyllos", "Agathe", "Bion", "Chloe", "Dion", "Elpis", "Gorgo", "Hagnon", "Isadora", "Korinna", "Lykos", "Melanthios", "Neaira",
	"Pasion", "Sappho", "Telesilla", "Xenon", "Ampelis", "Charmides", "Daphne", "Euphranor", "Ianthe", "Kimon", "Lampito", "Phokion"]
const FAMILY := ["Akamantides", "Alkmeonides", "Boutadai", "Charopides", "Eteoboutadai", "Philaides", "Kerykes", "Eumolpidai",
	"Lykomidai", "Phytalidai", "Gephyraioi", "Iamidai", "Klytiadai", "Bakchiadai", "Kypselidai", "Orthagoridai", "Aiakidai",
	"Neleidai", "Pelopidai", "Minyades", "Kodridai", "Medontidai", "Penthilidai", "Aleuadai", "Skopadai", "Echekratidai",
	"Damarchidai", "Thalassioi", "Karpathioi", "Phaistioi"]

var persons := {}                  # id -> record (see _new)
var _next := 1
var _rng := RandomNumberGenerator.new()
var _ids: Array = []
var _cursor := 0
var _at := {}                      # id -> Galaxy time its life was last looked at
## (kept current at every change - nothing ever counts everyone) who goes with whom:
## "crew:<tid>" -> {id: true} a ship's captain and crew, "fleet:<fid>" -> its
## sailors, a home ("st:<sid>", "town:<key>") -> the rest of those who live there.
var _by := {}
var _fleet_size := {}              # fleet id -> its size when last looked at (its losses: its sailors lost)
var _sync_t := 0.0
var populated := false
var _start_n := 3000               # (alive when the sector was peopled: births grow rarer past a quarter more)
var _alive_n := 3000


func reset() -> void:
	persons = {}
	_next = 1
	_ids = []
	_cursor = 0
	_at = {}
	_fleet_size = {}
	_by = {}
	_known_traders = {}
	populated = false
	_rng.seed = 7


# --- A new galaxy's people -------------------------------------------------------------

## Everyone for a new game: each station's staff and their households; each
## trader's captain and crew; each fleet's sailors.
func populate() -> void:
	reset()
	for sid in Galaxy.stations:
		_staff_station(str(sid))
	for tid in Galaxy.traders:
		crew_trader(str(tid), true)
	_finish_populate()


## The same a little a frame (a new game from the title: the loading screen keeps moving).
func populate_async(budget_us := 4000) -> void:
	reset()
	var t0 := Time.get_ticks_usec()
	for sid in Galaxy.stations:
		_staff_station(str(sid))
		if Time.get_ticks_usec() - t0 > budget_us:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	for tid in Galaxy.traders:
		crew_trader(str(tid), true)
		if Time.get_ticks_usec() - t0 > budget_us:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	_finish_populate()


func _finish_populate() -> void:
	_sync_fleets()
	_start_n = persons.size()
	_alive_n = _start_n
	populated = true


func _staff_station(sid: String) -> void:
	var emp := Galaxy.station_owner(sid)
	for s in STAFF:
		for k in int(s[1]):
			var p := _new(emp, "st:" + sid, str(s[0]), sid, _rng.randf_range(20.0, 62.0))
			# (a household: a partner at home, children - some of them)
			if _rng.randf() < 0.45:
				var q := _new(emp, "st:" + sid, "", "", clampf(float(p["age"]) + _rng.randf_range(-6.0, 6.0), 19.0, 70.0), str(p["f"]))
				_pair(p, q)
				for c in _rng.randi_range(0, 2) if float(p["age"]) < 50.0 else 0:
					var kid := _new(emp, "st:" + sid, "", "", _rng.randf_range(1.0, 15.0), str(p["f"]))
					_child(kid, p, q)


## A trader's captain (its owner) and crew - new hands for a new ship.
func crew_trader(tid: String, fresh := false) -> void:
	var r: Dictionary = Galaxy.traders.get(tid, {})
	if r.is_empty():
		return
	var emp := str(r.get("empire", ""))
	var home := "st:" + str(r.get("station", ""))
	if r.get("captain", "") == "" or not persons.has(str(r.get("captain", ""))):
		var c := _new(emp, home, "captain", tid, _rng.randf_range(28.0, 64.0))
		c["ship"] = tid
		r["captain"] = c["id"]
		_log(c, "Captain of the %s" % r["name"])
	for k in _rng.randi_range(1, CREW_MAX) - (1 if fresh else crew_of(tid).size()) + 1:
		var m := _new(emp, home, "crew", tid, _rng.randf_range(18.0, 55.0))
		_log(m, "Signed on to the %s" % r["name"])


func _new(emp: String, home: String, job: String, at: String, age: float, family := "") -> Dictionary:
	var id := "p%d" % _next
	_next += 1
	var p := {"id": id, "n": GIVEN[_rng.randi() % GIVEN.size()], "f": family if family != "" else FAMILY[_rng.randi() % FAMILY.size()],
		"age": snappedf(age, 0.1), "emp": emp, "home": home, "job": job, "at": at, "money": _rng.randi_range(100, 3000),
		"ship": "", "partner": "", "kids": [], "parents": [], "friends": [], "alive": true, "log": [], "born": Galaxy.time - age * YEAR}
	persons[id] = p
	_file(p, true)
	return p


func _pair(a: Dictionary, b: Dictionary) -> void:
	a["partner"] = b["id"]
	b["partner"] = a["id"]
	_log(a, "Partnered with %s" % full_name(b))
	_log(b, "Partnered with %s" % full_name(a))


func _child(kid: Dictionary, a: Dictionary, b: Dictionary) -> void:
	kid["parents"] = [a["id"], b["id"]]
	a["kids"].append(kid["id"])
	b["kids"].append(kid["id"])


func _log(p: Dictionary, text: String) -> void:
	var l: Array = p["log"]
	l.append([snappedf(Galaxy.time, 1.0), text])
	if l.size() > 10:
		l.pop_front()


# --- The towns' people ------------------------------------------------------------------

## A town's people (`key`: its planet and its name), made the first time
## anyone comes near it - households, each with a house of its own and a
## trade - then living on like everyone else. Its grown-ups' ids.
func town_folk(key: String, emp: String, city: bool) -> Array:
	var home := "town:" + key
	if not _by.has(home):
		var r := RandomNumberGenerator.new()
		r.seed = hash(key)
		for h in (12 if city else 6):
			var fam: String = FAMILY[r.randi() % FAMILY.size()]
			var a := _new(emp, home, TOWN_JOBS[r.randi() % TOWN_JOBS.size()], key, r.randf_range(20.0, 66.0), fam)
			a["house"] = h + 1
			_log(a, "Lives at house %d, %s" % [h + 1, key.get_slice(":", 1)])
			if r.randf() < 0.6:
				var b := _new(emp, home, TOWN_JOBS[r.randi() % TOWN_JOBS.size()] if r.randf() < 0.6 else "", key, clampf(float(a["age"]) + r.randf_range(-6.0, 6.0), 19.0, 72.0), fam)
				b["house"] = h + 1
				_pair(a, b)
				for c in r.randi_range(0, 3) if float(a["age"]) < 52.0 else 0:
					var kid := _new(emp, home, "", "", r.randf_range(1.0, 16.0), fam)
					kid["house"] = h + 1
					_child(kid, a, b)
	return _group(home).filter(func(i): return float(persons[i]["age"]) >= ADULT)


# --- Who and where -----------------------------------------------------------------------

func person(id: String) -> Dictionary:
	return persons.get(id, {})


func full_name(p: Dictionary) -> String:
	return "%s %s" % [p["n"], p["f"]] if not p.is_empty() else "?"


func job_name(p: Dictionary) -> String:
	if p.is_empty():
		return ""
	if float(p["age"]) < ADULT:
		return "child"
	return str(JOB_NAMES.get(p["job"], p["job"]))


## Where `p` is now: "st:<sid>" (at a station: its staff and household, a docked
## ship's people), "ship:<tid>" (aboard, travelling), "fleet:<fid>".
func where(p: Dictionary) -> String:
	match str(p["job"]):
		"crew", "captain":
			var r: Dictionary = Galaxy.traders.get(str(p["at"]), {})
			if r.is_empty():
				return str(p["home"])
			return "st:" + str(r["station"]) if r["state"] == "docked" else "ship:" + str(r["id"])
		"navy":
			return "fleet:" + str(p["at"])
	return str(p["home"])


## On duty now (a station's staff: shifts of a third of a day, two of three worked).
func on_shift(p: Dictionary) -> bool:
	if not p["job"] in ["bartender", "officer", "guard", "dock", "carrier"]:
		return false
	return (int(Galaxy.time / (DAY / 3.0)) + absi(hash(p["id"]))) % 3 != 0


## (Kept for callers: where everyone is follows from their ships' records, nothing to recount.)
func mark() -> void:
	pass


## Which group `p` is filed under (see _by).
func _key(p: Dictionary) -> String:
	match str(p["job"]):
		"crew", "captain":
			return "crew:" + str(p["at"])
		"navy":
			return "fleet:" + str(p["at"])
	return str(p["home"])


func _file(p: Dictionary, on: bool) -> void:
	var k := _key(p)
	if on:
		if not _by.has(k):
			_by[k] = {}
		_by[k][p["id"]] = true
	elif _by.has(k):
		(_by[k] as Dictionary).erase(p["id"])
		if (_by[k] as Dictionary).is_empty():
			_by.erase(k)


## A new job, post or home for `p` - every change of them through here (filed anew).
func _move(p: Dictionary, job: String, at: String, home := "") -> void:
	_file(p, false)
	p["job"] = job
	p["at"] = at
	if home != "":
		p["home"] = home
	if p["alive"]:
		_file(p, true)


func _group(k: String) -> Array:
	return (_by.get(k, {}) as Dictionary).keys()


func _refile() -> void:
	_by = {}
	for id in persons:
		if persons[id]["alive"]:
			_file(persons[id], true)


## A trader's people: its captain first, then its crew.
func crew_of(tid: String) -> Array:
	var out: Array = []
	for id in _group("crew:" + tid):
		if persons[id]["job"] == "captain":
			out.push_front(id)
		else:
			out.append(id)
	return out


## Everyone at station `sid` now: its staff and households, the people of the ships docked there.
func at_station(sid: String) -> Array:
	var out := _group("st:" + sid)
	for tid in Galaxy.traders:
		var r: Dictionary = Galaxy.traders[tid]
		if r["state"] == "docked" and str(r["station"]) == sid:
			out.append_array(_group("crew:" + str(tid)))
	return out


# --- Their lives -------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not populated or not Galaxy.active:
		return
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = 5.0
		_sync_traders()
		_sync_fleets()
	if _cursor >= _ids.size():
		_ids = persons.keys()
		_cursor = 0
	# (a share of them a frame, by time: everyone looked at every LIFE_TICK s)
	var share := mini(maxi(1, ceili(_ids.size() * delta / LIFE_TICK)), 40)
	var end := mini(_cursor + share, _ids.size())
	for j in range(_cursor, end):
		var p: Dictionary = persons.get(_ids[j], {})
		if p.is_empty() or not p["alive"]:
			continue
		var dt := clampf(Galaxy.time - float(_at.get(p["id"], Galaxy.time - LIFE_TICK)), 0.0, 600.0)
		_at[p["id"]] = Galaxy.time
		_live(p, dt)
	_cursor = end


func _live(p: Dictionary, dt: float) -> void:
	var was_child := float(p["age"]) < ADULT
	p["age"] = snappedf(float(p["age"]) + dt / YEAR, 0.01)
	if was_child and float(p["age"]) >= ADULT:
		_log(p, "Came of age")
	if float(p["age"]) > 70.0 and _rng.randf() < (float(p["age"]) - 70.0) * 0.0004 * dt / LIFE_TICK:
		_die(p, "Died of old age")
		return
	if float(p["age"]) < ADULT:
		return
	p["money"] = int(p["money"]) + int(float(WAGE.get(p["job"], 0)) * dt / DAY) - int(12.0 * dt / DAY)
	var mates := _group(_key(p))
	# Friends: of the people they work and live with.
	if mates.size() > 1 and (p["friends"] as Array).size() < 6 and _rng.randf() < 0.03 * dt / LIFE_TICK:
		var q: Dictionary = persons.get(mates[_rng.randi() % mates.size()], {})
		if not q.is_empty() and q["id"] != p["id"] and float(q["age"]) >= ADULT and not q["id"] in p["friends"]:
			p["friends"].append(q["id"])
			q["friends"].append(p["id"])
			_log(p, "Became friends with %s" % full_name(q))
			_log(q, "Became friends with %s" % full_name(p))
	# A partner: one of their friends.
	if p["partner"] == "" and float(p["age"]) < 60.0 and _rng.randf() < 0.0015 * dt / LIFE_TICK:
		for fid in p["friends"]:
			var q: Dictionary = persons.get(fid, {})
			if not q.is_empty() and q["alive"] and q["partner"] == "" and absf(float(q["age"]) - float(p["age"])) < 14.0:
				_pair(p, q)
				if p["job"] == "" or (p["job"] in WAGE and q["job"] in ["bartender", "officer", "guard", "dock", "carrier"]):
					_move(p, str(p["job"]), str(p["at"]), str(q["home"]))   # (moves in)
				break
	# Children.
	if p["partner"] != "" and float(p["age"]) < 45.0 and (p["kids"] as Array).size() < 3 and _alive_n < _start_n * 1.25 \
			and _rng.randf() < 0.0006 * dt / LIFE_TICK:   # (rarely - and fewer as the sector fills)
		var q: Dictionary = persons.get(p["partner"], {})
		if not q.is_empty() and q["alive"]:
			var kid := _new(str(p["emp"]), str(p["home"]), "", "", 0.0, str(p["f"]))
			_child(kid, p, q)
			_log(p, "A child: %s" % kid["n"])
			_log(q, "A child: %s" % kid["n"])
	# Work: the jobless look for it.
	if p["job"] == "":
		_find_work(p)
	elif p["job"] == "crew" and int(p["money"]) >= SHIP_PRICE and _rng.randf() < 0.05:
		_buy_ship(p)
	elif p["job"] != "navy" and p["job"] != "captain" and p["partner"] == "" and _at_war(str(p["emp"])) and _rng.randf() < 0.002 * dt / LIFE_TICK:
		_enlist(p)


func _at_war(e: String) -> bool:
	for o in Galaxy.MAJOR:
		if o != e and Galaxy.at_war(e, o):
			return true
	return false


## A job for one who has none: a vacancy at their station, else a berth on a
## ship there, else (at war) the navy.
func _find_work(p: Dictionary) -> void:
	var home := str(p["home"])
	if home.begins_with("town:"):   # (a town's grown children: a trade of their own)
		_move(p, TOWN_JOBS[_rng.randi() % TOWN_JOBS.size()], home.substr(5))
		_log(p, "Took up work as a %s" % JOB_NAMES[p["job"]])
		return
	if not home.begins_with("st:"):
		return
	var sid := home.substr(3)
	if not Galaxy.stations.has(sid):
		return
	var staff: Dictionary = {}
	for id in _group(home):
		var q: Dictionary = persons[id]
		if q["at"] == sid:
			staff[q["job"]] = int(staff.get(q["job"], 0)) + 1
	for s in STAFF:
		if int(staff.get(s[0], 0)) < int(s[1]):
			_move(p, str(s[0]), sid)
			_log(p, "Took work as a %s at %s" % [JOB_NAMES[s[0]], Galaxy.stations[sid]["name"]])
			return
	for tid in Galaxy.traders:
		var r: Dictionary = Galaxy.traders[tid]
		if r["state"] == "docked" and str(r["station"]) == sid and (_by.get("crew:" + str(tid), {}) as Dictionary).size() <= CREW_MAX:
			_move(p, "crew", str(tid))
			_log(p, "Signed on to the %s" % r["name"])
			return
	if _at_war(str(p["emp"])) and _rng.randf() < 0.3:
		_enlist(p)


func _enlist(p: Dictionary) -> void:
	var fl: Array = Fleets.fleets.values().filter(func(f): return f["empire"] == p["emp"])
	if fl.is_empty():
		return
	var f: Dictionary = fl[_rng.randi() % fl.size()]
	_move(p, "navy", str(f["id"]))
	_log(p, "Enlisted in the %s's navy" % Galaxy.empire_name(str(p["emp"])))


## Their savings on a ship of their own: a new trader at their ship's port, its captain.
func _buy_ship(p: Dictionary) -> void:
	var r: Dictionary = Galaxy.traders.get(str(p["at"]), {})
	if r.is_empty() or r["state"] != "docked":
		return
	var t: Dictionary = Galaxy.spawn_trader(str(r["station"]))
	if t.is_empty():
		return
	p["money"] = int(p["money"]) - SHIP_PRICE
	_move(p, "captain", str(t["id"]))
	p["ship"] = t["id"]
	t["captain"] = p["id"]
	t["empire"] = p["emp"] if p["emp"] != "" else t["empire"]
	_log(p, "Bought a ship of their own: the %s" % t["name"])
	crew_trader(str(t["id"]))


func _die(p: Dictionary, why: String) -> void:
	if not p["alive"]:
		return
	_file(p, false)
	p["alive"] = false
	_log(p, why)
	for k in ["partner"]:
		var q: Dictionary = persons.get(str(p[k]), {})
		if not q.is_empty() and q["alive"]:
			_log(q, "Lost their partner, %s" % full_name(p))
			q["partner"] = ""
	for kid in p["kids"]:
		var q: Dictionary = persons.get(kid, {})
		if not q.is_empty() and q["alive"]:
			_log(q, "Lost a parent, %s" % full_name(p))
	for par in p["parents"]:
		var q: Dictionary = persons.get(par, {})
		if not q.is_empty() and q["alive"]:
			_log(q, "Lost a child, %s" % full_name(p))
	if p["job"] == "captain":   # (the ship to its first mate - or laid up)
		var crew := crew_of(str(p["at"]))
		crew.erase(p["id"])
		if not crew.is_empty():
			var mate: Dictionary = persons[crew[0]]
			_move(mate, "captain", str(p["at"]))
			mate["ship"] = p["at"]
			Galaxy.traders.get(str(p["at"]), {})["captain"] = mate["id"]
			_log(mate, "Took command of the %s" % Galaxy.traders.get(str(p["at"]), {}).get("name", "ship"))


## A trader destroyed (in your system: you saw it): its captain and crew with it.
func ship_lost(tid: String, why: String) -> void:
	for id in crew_of(tid):
		_die(persons[id], why)


## Ships come and go: new traders crewed; the people of a ship that's gone
## (hijacked, lost with its port) ashore at its last port, between jobs.
var _known_traders := {}
var _prune_t := 60.0


func _sync_traders() -> void:
	for tid in Galaxy.traders:
		var r: Dictionary = Galaxy.traders[tid]
		if str(r.get("captain", "")) == "" or not persons.has(str(r.get("captain", ""))) or not persons[str(r["captain"])]["alive"]:
			crew_trader(str(tid))
	# (ships gone since the last look: their people ashore, between jobs)
	for tid in _known_traders:
		if Galaxy.traders.has(tid):
			continue
		for id in _group("crew:" + str(tid)):
			var p: Dictionary = persons[id]
			_log(p, "Lost their ship")
			_move(p, "", "")
			p["ship"] = ""
	_known_traders = {}
	for tid in Galaxy.traders:
		_known_traders[tid] = true


## The fleets' sailors: one a warship; a fleet's losses are its sailors'
## deaths; a fleet gone home - or wiped out - its people home or mourned.
func _sync_fleets() -> void:
	var now := {}
	for fid in Fleets.fleets:
		now[str(fid)] = int(Fleets.fleets[fid]["size"])
	var crews := {}
	for k in _by:
		if str(k).begins_with("fleet:"):
			crews[str(k).substr(6)] = (_by[k] as Dictionary).keys()
	for fid in _fleet_size:
		if not now.has(fid):   # (gone: wiped out if it was losing, else home)
			for id in crews.get(fid, []):
				var p: Dictionary = persons[id]
				if int(_fleet_size[fid]) <= 2:
					_die(p, "Killed in battle with the fleet")
				else:
					_move(p, "", "")
					_log(p, "Came home from the war")
	for fid in now:
		var f: Dictionary = Fleets.fleets[fid]
		var have: Array = crews.get(fid, [])
		while have.size() > now[fid]:   # (ships lost: their sailors)
			var id: String = have.pop_back()
			_die(persons[id], "Killed in battle at %s" % Galaxy.system(str(f["system"])).get("name", "?"))
		while have.size() < now[fid]:   # (new ships: sailors from the empire's people)
			var p := _new(str(f["empire"]), "st:" + _home_station(str(f["empire"])), "navy", fid, _rng.randf_range(18.0, 40.0))
			_log(p, "Enlisted in the %s's navy" % Galaxy.empire_name(str(f["empire"])))
			have.append(p["id"])
	_fleet_size = now
	_prune_t -= 5.0
	if _prune_t > 0.0:
		return
	_prune_t = 60.0
	# (the long dead out of the records - their names live on in the logs of those who knew them)
	var alive := 0
	for id in persons.keys():
		var p: Dictionary = persons[id]
		if p["alive"]:
			alive += 1
		elif Galaxy.time - float(p["log"][-1][0] if not (p["log"] as Array).is_empty() else 0.0) > YEAR * 2.0:
			persons.erase(id)
			_at.erase(id)
	_alive_n = alive


func _home_station(e: String) -> String:
	var own: Array = Galaxy.stations.keys().filter(func(s): return Galaxy.station_owner(s) == e)
	return str(own[_rng.randi() % own.size()]) if not own.is_empty() else str(Galaxy.stations.keys()[0])


# --- What they tell you ----------------------------------------------------------------

## A few sentences of who `p` is: their name and work, their family, their friends, lately.
func story(id: String) -> Array:
	var p := person(id)
	if p.is_empty():
		return []
	var lines: Array = []
	var place := ""
	if p["job"] in ["crew", "captain"]:
		var r: Dictionary = Galaxy.traders.get(str(p["at"]), {})
		if not r.is_empty():
			var dest: Dictionary = Galaxy.stations.get(str(r.get("dest", "")), {})
			if p["job"] == "captain":
				place = "I captain the %s, my own ship" % r["name"]
			else:
				place = "I crew the %s under Captain %s" % [r["name"], full_name(person(str(r.get("captain", ""))))]
			if r["state"] == "docked":
				place += " - we sail again soon"
			elif not dest.is_empty():
				place += " - bound for %s" % dest["name"]
	elif p["job"] == "navy":
		place = "I serve in the %s's navy" % Galaxy.empire_name(str(p["emp"]))
	elif str(p["home"]).begins_with("town:"):
		var town := str(p["home"]).get_slice(":", 2)
		place = ("I'm a %s here in %s" % [job_name(p), town]) if p["job"] != "" else "I keep house here in %s" % town
		if p.has("house"):
			place += " - house %d is ours" % int(p["house"])
	elif str(p["home"]).begins_with("st:") and Galaxy.stations.has(str(p["home"]).substr(3)):
		var sname: String = Galaxy.stations[str(p["home"]).substr(3)]["name"]
		place = ("I'm the %s here at %s" % [job_name(p), sname]) if p["job"] != "" else "I live here at %s" % sname
	lines.append("%s. %s, %d years old." % [place, full_name(p), int(p["age"])])
	var fam: Array = []
	var q := person(str(p["partner"]))
	if not q.is_empty():
		fam.append("my partner %s (%s)" % [q["n"], job_name(q)])
	var kids: Array = (p["kids"] as Array).map(func(k): return person(k)).filter(func(k): return not k.is_empty() and k["alive"])
	if not kids.is_empty():
		fam.append("%s: %s" % ["our child" if kids.size() == 1 else "our children", ", ".join(kids.map(func(k): return "%s (%d)" % [k["n"], int(k["age"])]))])
	if not fam.is_empty():
		lines.append("Family: " + "; ".join(fam) + ".")
	var fr: Array = (p["friends"] as Array).map(func(k): return person(k)).filter(func(k): return not k.is_empty() and k["alive"]).slice(0, 3)
	if not fr.is_empty():
		lines.append("Friends: " + ", ".join(fr.map(func(k): return "%s the %s" % [k["n"], job_name(k)])) + ".")
	var lg: Array = (p["log"] as Array).slice(-3)
	if not lg.is_empty():
		lines.append("Lately: " + "; ".join(lg.map(func(e): return str(e[1]))) + ".")
	return lines


# --- Saved -------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"next": _next, "persons": persons, "fleets": _fleet_size, "populated": populated, "start": _start_n}


func load_save_data(d: Dictionary) -> void:
	reset()
	if d.is_empty() or not d.get("populated", false):
		populate()   # (a save from before the people: theirs made now)
		return
	persons = d.get("persons", {})
	_next = int(d.get("next", persons.size() + 1))
	_fleet_size = d.get("fleets", {})
	_start_n = int(d.get("start", persons.size()))
	for id in persons:   # (JSON: numbers come back as floats; lists as untyped arrays)
		var p: Dictionary = persons[id]
		for k in ["kids", "parents", "friends", "log"]:
			if not p.get(k) is Array:
				p[k] = []
	_refile()
	populated = true
