class_name ShipDesigns
## The ship classes flown in the game: the hand-traced designs (TracedShips).
## Independent designs fly for everyone; an empire's own designs (traced with
## "empire") are flown by that empire first. Civil roles come from the class:
## freighters trade, explorers / couriers explore, Hornets mine.

const CIVIL := {"freighter": "trader", "explorer": "explorer", "courier": "explorer"}
const MINERS := ["traced_hornet"]
## Empires without a reference sheet of their own fly the independent designs
## that match their colours (Mycenae: olive, gold, bronze and red-cream hulls).
const AFFINITY := {"mycenae": ["traced_bulwark", "traced_hornet", "traced_ember", "traced_bastion", "traced_atlas", "traced_halo"]}

static var _types := {}

## The capital classes - cruisers, battleships and dreadnoughts, each empire's
## (and the independents') own: no sheets of their own yet, so each is drawn
## with one of its empire's biggest hulls ("art"), larger. [name, art, tint].
const CAPITALS := {
	"cruiser": {
		"": ["Citadel", "traced_bastion"], "minoa": ["Knossos", "traced_minoa_taurus"], "pirates": ["Marauder", "traced_pirate_skullsun"],
		"athens": ["Strategos", "traced_athens_pentathlon"], "sparta": ["Agoge", "traced_sparta_lykourgos"],
		"ionia": ["Priene", "traced_ionia_miletos"], "cyclades": ["Delos", "traced_cyclades_longboat"]},
	"battleship": {
		"": ["Colossus", "traced_bastion"], "minoa": ["Phaistos", "traced_minoa_taurus"], "pirates": ["Warlord", "traced_pirate_ironwheel"],
		"athens": ["Acropolis", "traced_athens_parthenon_wheel"], "sparta": ["Thermopylae", "traced_sparta_thermopylae"],
		"ionia": ["Ephesos", "traced_ionia_miletos"], "cyclades": ["Naxos", "traced_cyclades_sanctuary"]},
	"dreadnought": {
		"": ["Monolith", "traced_bastion"], "minoa": ["Labyrinth", "traced_minoa_taurus"], "pirates": ["Black Tide", "traced_pirate_galleon"],
		"athens": ["Pallas", "traced_athens_parthenon_wheel"], "sparta": ["Lykourgos", "traced_sparta_thermopylae"],
		"ionia": ["Halikarnassos", "traced_ionia_miletos"], "cyclades": ["Santorini", "traced_cyclades_sanctuary"]},
}
## Each capital class: [hull, shields, speed, length on screen, list price,
## the class's name, damage a second (spread over its guns: Enemy batteries)].
const CAPITAL_STATS := {
	"cruiser": [450.0, 260.0, 120.0, 330.0, 16000, "Cruiser", 40.0],
	"battleship": [800.0, 420.0, 95.0, 430.0, 24000, "Battleship", 70.0],
	"dreadnought": [1300.0, 650.0, 75.0, 540.0, 34000, "Dreadnought", 110.0],
}
const CAPITAL_CLASSES := ["cruiser", "battleship", "dreadnought"]


static func _ensure() -> void:
	if not _types.is_empty():
		return
	for tid in TracedShips.ids():
		var t := TracedShips.type_of(tid)
		var role: String = "miner" if tid in MINERS or TracedShips.def(tid).get("civil", "") == "miner" else CIVIL.get(t["class"], "")
		if role != "":
			t["faction"] = "neutral"
			t["role"] = role
			t["travel_bias"] = {"trader": 0.85, "miner": 0.5, "explorer": 0.3}[role]
		_types[tid] = t
	for cls in CAPITALS:
		var cs: Array = CAPITAL_STATS[cls]
		for e in CAPITALS[cls]:
			var d: Array = CAPITALS[cls][e]
			if not _types.has(d[1]):
				continue
			var art: Dictionary = _types[d[1]]
			var name := "%s-class %s" % [d[0], cs[5]]
			_types["cap_%s_%s" % [e if e != "" else "independent", cls]] = {"name": name, "empire_style": e, "class": cls,
				"art": d[1], "price": cs[4], "capital": true,
				"desc": ("An independent %s: %s." % [cs[5].to_lower(), name]) if e == "" else ("%s of the %s." % [name, Galaxy.EMPIRES[e]["name"]]),
				"length": cs[3], "hull": cs[0], "shields": cs[1], "speed": cs[2], "fire_interval": 1.0, "damage": cs[6] / 3.0,
				"bullet_speed": 650.0, "shots": 3, "aggro": 900.0, "distance": 520.0, "color": art.get("color", Color(1.0, 0.6, 0.2))}


static func types() -> Dictionary:
	_ensure()
	return _types


static func ids() -> Array:
	_ensure()
	return _types.keys()


## Who flies a design: its empire ("independent" for the unclaimed ones;
## the designs an empire without a sheet of its own has adopted - AFFINITY -
## are that empire's).
static func owner_of(id: String) -> String:
	_ensure()
	var t: Dictionary = _types.get(id, {})
	if t.is_empty():
		return ""
	var e: String = t.get("empire_style", "")
	if e != "":
		return e
	for k in AFFINITY:
		if id in AFFINITY[k]:
			return k
	return "independent"


## A class for an empire (or "independent") with one of the given hull
## classes ("fighter", "freighter", ...) or civil roles ("trader", "miner",
## "explorer"): only that empire's own designs - a ship always looks like
## who it flies for. (None of its own for that job: an independent one.)
static func pick(e: String, keys: Array) -> String:
	_ensure()
	var own := []
	var any := []
	for id in _types:
		var t: Dictionary = _types[id]
		if t.get("unique", false) or not (t["class"] in keys or t.get("role", "") in keys):
			continue
		var o := owner_of(id)
		if o == e:
			own.append(id)
		elif o == "independent":
			any.append(id)
	if not own.is_empty():
		return own.pick_random()
	return any.pick_random() if not any.is_empty() else ""


static func warship(e: String) -> String:
	return pick(e, ["fighter", "fighter", "interceptor", "gunship", "frigate"])


## A fleet's flagship: a capital ship of the empire's (or the independents')
## by the fleet's size - a cruiser from 6 ships, a battleship from 9, a
## dreadnought for a full 12. "" for a smaller fleet.
static func flagship(e: String, size: int) -> String:
	if size < 6:
		return ""
	var cls := "dreadnought" if size >= 12 else ("battleship" if size >= 9 else "cruiser")
	return pick(e, [cls])
