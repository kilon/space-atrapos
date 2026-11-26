extends Node
## War fleets (autoload "Fleets"): every empire keeps fleets of MIN_SIZE to
## MAX_SIZE warships. Defence fleets hold its systems (about one for every
## three), and go to the help of a system under siege nearby; at war, an
## empire sends invasion fleets against the enemy systems on its border.
##
## Invasions are events: an empire gathers two or three fleets at a staging
## system on its border (each from a system of its own); when they're all
## there (or after GATHER_TIME) they set out together against the target.
## A station under siege sends a distress call (distress): the defence fleets
## of its owner and of the owner's allies within DISTRESS_JUMPS answer it;
## allies go home when the danger is over.
##
## Away from you it's all worked out here, every TICK seconds: fleets move
## along the gate lanes (HOP_TIME a jump); where enemies meet they trade
## losses; an invasion with no defenders left wears down the stations of the
## empires it's at war with (Galaxy.damage_station) - destroyed at 0 - and
## when the system's owner has no station left there, the system falls to
## the invader (its fleet stays on to defend it). A peace sends invasions home.
##
## In the system you're in the fleets are real ships (main.gd spawns them,
## and the ones arriving: fleet_arrived): defenders patrol, invaders go for
## the stations; each ship lost counts (ship_lost). While you're there, that
## system's fleets don't move and its fight isn't worked out here.

signal fleet_arrived(fleet: Dictionary)
signal changed

const TICK := 5.0
const HOP_TIME := 30.0
const MIN_SIZE := 3
const MAX_SIZE := 12
## Station damage an invading ship does a tick (a 10-ship fleet: 6 a tick,
## a healthy station falls in about a minute and a half of siege).
const SIEGE_DAMAGE := 0.6
## A station mends this much a tick when nobody besieges its system.
const MEND := 0.4
## An invasion's fleets wait at most this long for each other at the staging system.
const GATHER_TIME := 120.0
## How far (gate jumps) a distress call reaches, and how many fleets answer it.
const DISTRESS_JUMPS := 4
const DISTRESS_ANSWER := 2
## A system's distress call is sent again at most this often (s).
const DISTRESS_EVERY := 60.0

var fleets := {}   # id -> {id, empire, mission ("defend" / "invade"), size, system, route: [], t, target;
                   #  invasions: event, stage, waiting; answering a distress call: answering}
var _next := 1
var _clock := 0.0     # the simulation's own time (s) - for gathering and distress calls
var _distress := {}   # system id -> _clock of its last distress call
var _t := TICK
var _rng := RandomNumberGenerator.new()


func reset() -> void:
	fleets = {}
	_next = 1
	_clock = 0.0
	_distress = {}
	_rng.seed = 11
	_t = TICK
	_staff()


func _process(delta: float) -> void:
	if not Galaxy.active:
		return
	_t -= delta
	if _t <= 0.0:
		_t = TICK
		_tick()


func _tick() -> void:
	_clock += TICK
	_staff()
	_move()
	_fight()
	_mend()
	changed.emit()


# --- Queries ---------------------------------------------------------------------------

func in_system(sys_id: String) -> Array:
	return fleets.values().filter(func(f): return f["system"] == sys_id)


## Is this station's system besieged by an empire at war with its owner?
func besieged(station_id: String) -> bool:
	var st: Dictionary = Galaxy.stations.get(station_id, {})
	if st.is_empty():
		return false
	var owner := Galaxy.station_owner(station_id)
	for f in fleets.values():
		if f["system"] == st["system"] and f["mission"] == "invade" and f["route"].is_empty() and not f.get("waiting", false) and Galaxy.at_war(f["empire"], owner):
			return true
	return false


## The empires besieging a system (for the defence missions).
func besiegers(sys_id: String) -> Array:
	var out := []
	for f in fleets.values():
		if f["system"] == sys_id and f["mission"] == "invade" and f["route"].is_empty() and not f.get("waiting", false) and not f["empire"] in out:
			out.append(f["empire"])
	return out


func ship_lost(fleet_id: String) -> void:
	var f: Dictionary = fleets.get(fleet_id, {})
	if f.is_empty():
		return
	f["size"] -= 1
	if f["size"] <= 0:
		fleets.erase(fleet_id)
		_news("%s: a %s %s fleet has been wiped out." % [Galaxy.system(f["system"]).get("name", "?"),
			Galaxy.EMPIRES[f["empire"]]["short"], "invasion" if f["mission"] == "invade" else "defence"], "news")
	changed.emit()


# --- Fleets come and go ---------------------------------------------------------------------

func _owned(e: String) -> Array:
	return Galaxy.systems.keys().filter(func(id): return Galaxy.owner_of(id) == e)


## Keeps every empire's defence fleets up (one for three systems) and, at war,
## an invasion going against each enemy it borders.
func _staff() -> void:
	for e in Galaxy.MAJOR:
		var own := _owned(e)
		if own.is_empty():
			continue
		var mine: Array = fleets.values().filter(func(f): return f["empire"] == e)
		var defenders := mine.filter(func(f): return f["mission"] == "defend").size()
		if defenders < ceili(own.size() / 3.0):
			var at: String = own[_rng.randi() % own.size()]
			_new_fleet(e, "defend", at, _rng.randi_range(MIN_SIZE, 8), [])
		for o in Galaxy.MAJOR:
			if o == e or not Galaxy.at_war(e, o):
				continue
			if mine.any(func(f): return f["mission"] == "invade" and Galaxy.owner_of(f["target"]) == o):
				continue
			if _rng.randf() > 0.25:
				continue   # (not every tick: invasions gather)
			# An enemy system next to ours.
			var fronts := []
			for id in _owned(o):
				if id == Galaxy.HOME:
					continue   # (the story's home holds)
				for n in Galaxy.neighbors(id):
					if Galaxy.owner_of(n) == e:
						fronts.append([n, id])
						break
			if fronts.is_empty():
				continue
			var pick: Array = fronts[_rng.randi() % fronts.size()]
			_launch_invasion(e, pick[0], pick[1])


## An invasion event: two or three fleets, each from a system of `e` near
## the staging system `stage` (next to `target`), gather there and then set
## out together.
func _launch_invasion(e: String, stage: String, target: String) -> void:
	var event := "inv%d" % _next
	var homes: Array = [stage]
	for n in Galaxy.neighbors(stage):
		if Galaxy.owner_of(n) == e:
			homes.append(n)
	var count := 2 + (1 if _rng.randf() < 0.5 else 0)
	var total := 0
	for i in count:
		var home: String = homes[i % homes.size()] if i == 0 else homes[_rng.randi() % homes.size()]
		var route := [] if home == stage else _path(home, stage, e)
		var f := _new_fleet(e, "invade", home, _rng.randi_range(4, 10), route)
		f["target"] = target
		f["event"] = event
		f["stage"] = stage
		f["waiting"] = true
		f["since"] = _clock
		total += int(f["size"])
	_news("%s: the %s gathers %d fleets (%d warships) for an invasion of %s." % [Galaxy.system(stage)["name"],
		Galaxy.empire_name(e), count, total, Galaxy.system(target)["name"]], "danger" if target == Galaxy.current_system else "news")


## The fleets of an invasion event.
func event_fleets(event: String) -> Array:
	return fleets.values().filter(func(f): return f.get("event", "") == event)


## An invasion's fleets all at the staging system (or tired of waiting): off
## they go together.
func _gather(f: Dictionary) -> void:
	if not f.get("waiting", false) or not f["route"].is_empty() or f["system"] != f.get("stage", ""):
		return
	var mates := event_fleets(f["event"])
	var ready := mates.all(func(g): return g["system"] == g["stage"] and g["route"].is_empty())
	if not ready and _clock - float(f.get("since", 0.0)) < GATHER_TIME:
		return
	var ships := 0
	var going := 0
	for g in mates:
		if g.get("waiting", false) and g["system"] == g["stage"] and g["route"].is_empty():
			g["waiting"] = false
			g["route"] = [g["target"]]
			ships += int(g["size"])
			going += 1
	if going > 0:
		_news("%s: the %s's combined invasion - %d fleets, %d warships - sets out for %s." % [Galaxy.system(f["stage"])["name"],
			Galaxy.empire_name(f["empire"]), going, ships, Galaxy.system(f["target"])["name"]],
			"danger" if f["target"] == Galaxy.current_system else "news")


## A station in `sys_id` (run by `victim`) is under attack by `attacker`: its
## distress call brings the idle defence fleets of the victim and its allies
## (those at war with the attacker) within DISTRESS_JUMPS - at most
## DISTRESS_ANSWER of them, nearest first. At most once every DISTRESS_EVERY s.
func distress(sys_id: String, victim: String, attacker: String) -> Array:
	if _clock - float(_distress.get(sys_id, -INF)) < DISTRESS_EVERY:
		return []
	_distress[sys_id] = _clock
	var cands := []
	for f in fleets.values():
		if f["mission"] != "defend" or not f["route"].is_empty() or f["system"] == sys_id:
			continue
		var e: String = f["empire"]
		if e != victim and not (Galaxy.allied(e, victim) and Galaxy.at_war(e, attacker)):
			continue
		if f["system"] == Galaxy.current_system:
			continue   # (in your system: real ships - they stay)
		var p := _path(f["system"], sys_id, e)
		if p.size() >= 1 and p.size() <= DISTRESS_JUMPS:
			cands.append([p.size(), f, p])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var answered := []
	for c in cands.slice(0, DISTRESS_ANSWER):
		c[1]["route"] = c[2]
		c[1]["answering"] = sys_id
		answered.append(c[1])
	var sys_name: String = Galaxy.system(sys_id).get("name", "?")
	if answered.is_empty():
		_news("%s sends a distress call - no fleet is near enough to answer." % sys_name, "danger" if sys_id == Galaxy.current_system else "news")
	else:
		var who := ", ".join(answered.map(func(f): return "%s (%d ships)" % [Galaxy.EMPIRES[f["empire"]]["short"], f["size"]]))
		_news("Distress call from %s: %s answering." % [sys_name, who], "danger" if sys_id == Galaxy.current_system else "news")
	changed.emit()
	return answered


func _new_fleet(e: String, mission: String, at: String, size: int, route: Array) -> Dictionary:
	var id := "f%d" % _next
	_next += 1
	var f := {"id": id, "empire": e, "mission": mission, "size": clampi(size, MIN_SIZE, MAX_SIZE), "system": at,
		"route": route.duplicate(), "t": 0.0, "target": at}
	fleets[id] = f
	if at == Galaxy.current_system:
		fleet_arrived.emit(f)
	return f


# --- Moving ---------------------------------------------------------------------------------

func _move() -> void:
	for f in fleets.values():
		if f["system"] == Galaxy.current_system:
			continue   # (in your system: real ships, they stay)
		# A peace (or a target already taken) ends an invasion: home to defend.
		if f["mission"] == "invade" and not Galaxy.at_war(f["empire"], Galaxy.owner_of(f["target"])):
			f["mission"] = "defend"
			var own := _owned(f["empire"])
			if not own.is_empty() and not f["system"] in own:
				f["route"] = _path(f["system"], own[0], f["empire"])
		# An invasion gathering at its staging system: off together when all are there.
		_gather(f)
		# Defenders far from home (answering an ally's call) with nothing to
		# fight any more: home.
		if f["mission"] == "defend" and f["route"].is_empty() and Galaxy.owner_of(f["system"]) != f["empire"] \
				and besiegers(f["system"]).is_empty():
			var own_sys := _owned(f["empire"])
			if not own_sys.is_empty():
				own_sys.sort_custom(func(a, b): return _path(f["system"], a, "").size() < _path(f["system"], b, "").size())
				f["route"] = _path(f["system"], own_sys[0], f["empire"])
				f.erase("answering")
		if f["route"].is_empty():
			continue
		f["t"] += TICK
		if f["t"] < HOP_TIME:
			continue
		f["t"] = 0.0
		f["system"] = f["route"].pop_front()
		if f["system"] == Galaxy.current_system:
			fleet_arrived.emit(f)
			if f["mission"] == "invade" and f["route"].is_empty():
				_news("An invasion fleet of the %s has arrived here: %d warships." % [Galaxy.empire_name(f["empire"]), f["size"]], "danger")


## The way from a to b (the systems after a), through any systems.
func _path(a: String, b: String, _e: String) -> Array:
	var p := Galaxy.find_route(a, b)
	return p.slice(1) if p.size() > 1 else []


# --- Fighting (away from you) ----------------------------------------------------------------

func _fight() -> void:
	var by := {}
	for f in fleets.values():
		if f["route"].is_empty() and f["system"] != Galaxy.current_system:
			if not by.has(f["system"]):
				by[f["system"]] = []
			by[f["system"]].append(f)
	for sys_id in by:
		var here: Array = by[sys_id]
		for f in here:
			if not fleets.has(f["id"]):
				continue
			var foes: Array = here.filter(func(g): return fleets.has(g["id"]) and Galaxy.at_war(g["empire"], f["empire"]))
			if not foes.is_empty():
				# A battle: losses by the other side's strength.
				var strength := 0
				for g in foes:
					strength += g["size"]
				var loss := int(_rng.randf() * 0.25 * strength + _rng.randf())
				f["size"] -= loss
				if f["size"] <= 0:
					fleets.erase(f["id"])
					_news("%s: the %s %s fleet was destroyed in battle." % [Galaxy.system(sys_id)["name"], Galaxy.EMPIRES[f["empire"]]["short"],
						"invasion" if f["mission"] == "invade" else "defence"], "news")
				continue
			if f["mission"] != "invade":
				continue
			# A siege: the stations of the empires it's at war with.
			var targets: Array = Galaxy.system(sys_id).get("stations", []).filter(func(sid): return Galaxy.at_war(f["empire"], Galaxy.station_owner(sid)))
			if not targets.is_empty():
				targets.sort_custom(func(a, b): return Galaxy.station_health(a) < Galaxy.station_health(b))
				Galaxy.damage_station(targets[0], f["size"] * SIEGE_DAMAGE)
				# Stations shoot back.
				if _rng.randf() < 0.15:
					f["size"] -= 1
					if f["size"] <= 0:
						fleets.erase(f["id"])
				continue
			_capture(sys_id, f)


## No station of the owner left: the system falls to the invader.
func _capture(sys_id: String, f: Dictionary) -> void:
	var owner := Galaxy.owner_of(sys_id)
	if owner == f["empire"] or not Galaxy.at_war(owner, f["empire"]):
		f["mission"] = "defend"
		return
	if Galaxy.system(sys_id)["stations"].any(func(sid): return Galaxy.station_owner(sid) == owner):
		return
	Galaxy.systems[sys_id]["owner"] = f["empire"]
	Galaxy.systems[sys_id]["control"] = 40.0
	f["mission"] = "defend"
	_news("CONQUEST: %s has fallen to the %s's invasion (taken from the %s)." % [Galaxy.system(sys_id)["name"], Galaxy.empire_name(f["empire"]), Galaxy.empire_name(owner)], "danger")
	Galaxy.politics_changed.emit()


func _mend() -> void:
	for sid in Galaxy.stations:
		var st: Dictionary = Galaxy.stations[sid]
		if float(st.get("health", 100.0)) < 100.0 and not besieged(sid):
			Galaxy.repair_station(sid, MEND)


func _news(text: String, kind: String) -> void:
	Galaxy._post(text, kind)


# --- Saving ---------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	return {"fleets": fleets.duplicate(true), "next": _next, "clock": _clock}


func load_save_data(d: Dictionary) -> void:
	if d.is_empty():
		return
	fleets = {}
	for id in d.get("fleets", {}):
		var f: Dictionary = d["fleets"][id]
		f["size"] = int(f["size"])
		f["t"] = float(f.get("t", 0.0))
		f["route"] = Array(f.get("route", []))
		fleets[id] = f
	_next = int(d.get("next", fleets.size() + 1))
	_clock = float(d.get("clock", 0.0))
	_distress = {}
