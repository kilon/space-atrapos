class_name Upgrades
extends RefCounted
## Component upgrades: every part of the ship and the automaton carries stats
## that can be raised, up to MAX_LEVEL levels each (STATS: some fifty, from
## hull and shields to accuracy, critical hits, every resistance, fuel use and
## mining yield). Bought at a station's workshop (UPGRADES) or fitted on board
## from a manufactured Upgrade Kit (made and fitted at the ship's fabricator:
## DeviceMenu).
## The levels: the player's "upgrades" {"ship": {"<part>:<stat>": level}, "automaton": {...}}.
##   Upgrades.mod(data.upgrades, "ship", "accuracy")

const MAX_LEVEL := 5
const PRICE_GROWTH := 1.7

## body -> part -> [[stat key, name, per level, base price, how it shows ("%", "+", "-%", "s")]]
const STATS := {
	"ship": {
		"sensors": [["accuracy", "Accuracy", 0.02, 900, "%"], ["range_mult", "Weapon range", 0.04, 800, "%"],
			["crit_chance", "Critical chance", 0.02, 1100, "%"], ["probe_strength", "Probe strength", 0.12, 900, "%"], ["mining_yield", "Ore yield", 0.08, 700, "%"]],
		"weapons": [["damage_mult", "Weapon damage", 0.04, 1200, "%"], ["fire_rate_mult", "Rate of fire", -0.03, 1100, "-%"],
			["crit_mult", "Critical damage", 0.12, 900, "%"], ["mining_speed", "Mining speed", 0.08, 700, "%"]],
		"reactor": [["shield_regen_mult", "Shield recharge", 0.08, 900, "%"], ["afterburner_cd_mult", "System cooldowns", -0.06, 800, "-%"], ["refine_speed", "Refinery speed", 0.1, 700, "%"]],
		"shields": [["max_shields", "Shield strength", 12.0, 900, "+"], ["regen_delay", "Shield recharge delay", -0.3, 800, "s"],
			["resist_energy", "Energy resistance", 0.03, 800, "%"], ["resist_beam", "Beam resistance", 0.03, 800, "%"]],
		"thrusters": [["handling_mult", "Handling", 0.05, 800, "%"], ["evasion", "Evasion", 0.02, 1000, "%"]],
		"engines": [["speed_mult", "Top speed", 0.04, 1000, "%"], ["fuel_efficiency", "Fuel efficiency", 0.06, 700, "%"]],
		"fuel": [["fuel_capacity", "Fuel tank", 15.0, 600, "+"], ["cargo", "Hold space", 4.0, 900, "slot"]],
		"plating": [["max_hull", "Hull strength", 15.0, 900, "+"], ["hull_taken_mult", "Armour", -0.03, 1000, "-%"],
			["resist_kinetic", "Kinetic resistance", 0.03, 800, "%"], ["resist_explosive", "Explosive resistance", 0.03, 800, "%"],
			["resist_heat", "Heat resistance", 0.03, 700, "%"], ["resist_cold", "Cold resistance", 0.03, 700, "%"],
			["resist_electric", "Electric resistance", 0.03, 800, "%"]],
	},
	"automaton": {
		"optics": [["accuracy", "Accuracy", 0.02, 500, "%"], ["range_mult", "Weapon reach", 0.04, 450, "%"], ["crit_chance", "Critical chance", 0.02, 600, "%"]],
		"core": [["max_hp", "Health", 10.0, 500, "+"], ["regen_mult", "Healing", 0.1, 450, "%"], ["overcharge_mult", "Overcharge time", 0.1, 400, "%"]],
		"arms": [["damage_mult", "Damage", 0.04, 600, "%"], ["fire_rate_mult", "Rate of fire", -0.03, 550, "-%"], ["crit_mult", "Critical damage", 0.12, 450, "%"]],
		"cooling": [["resist_heat", "Heat resistance", 0.03, 400, "%"], ["resist_cold", "Cold resistance", 0.03, 400, "%"], ["resist_energy", "Energy resistance", 0.03, 450, "%"]],
		"legs": [["speed_mult", "Walking speed", 0.04, 500, "%"], ["evasion", "Evasion", 0.02, 550, "%"],
			["jet_pack", "Jet thrusters", 1.0, 900, "lvl"]],
		"frame": [["hurt_taken_mult", "Armour", -0.03, 550, "-%"], ["resist_kinetic", "Kinetic resistance", 0.03, 450, "%"],
			["resist_explosive", "Explosive resistance", 0.03, 450, "%"], ["resist_electric", "Electric resistance", 0.03, 450, "%"],
			["resist_beam", "Beam resistance", 0.03, 450, "%"]],
	},
}
## Critical hits: a shot's chance to strike a weak spot (no upgrades: CRIT_BASE) for CRIT_MULT x damage.
const CRIT_BASE := 0.04
const CRIT_MULT := 1.6


## Every stat a body's parts carry: [{part, key, name, per, price, fmt, id ("<part>:<key>")}].
static func list(which: String) -> Array:
	var out := []
	for pid in STATS[which]:
		for st in STATS[which][pid]:
			out.append({"part": pid, "key": st[0], "name": st[1], "per": st[2], "price": st[3], "fmt": st[4], "id": "%s:%s" % [pid, st[0]]})
	return out


static func find(which: String, id: String) -> Dictionary:
	for st in list(which):
		if st["id"] == id:
			return st
	return {}


## A stat's level now.
static func level(ups: Variant, which: String, id: String) -> int:
	if not ups is Dictionary or not (ups as Dictionary).get(which) is Dictionary:
		return 0
	return int(ups[which].get(id, 0))


## The price of its next level (0 at the top).
static func price(which: String, id: String, lvl: int) -> int:
	var st := find(which, id)
	if st.is_empty() or lvl >= MAX_LEVEL:
		return 0
	return snappedi(roundi(float(st["price"]) * pow(PRICE_GROWTH, lvl)), 10)


## Raises a stat a level (the levels in `ups`, made if missing). False at the top.
static func raise(ups: Dictionary, which: String, id: String) -> bool:
	if find(which, id).is_empty():
		return false
	if not ups.get(which) is Dictionary:
		ups[which] = {}
	var l := int(ups[which].get(id, 0))
	if l >= MAX_LEVEL:
		return false
	ups[which][id] = l + 1
	return true


## The sum of a stat over a body's upgraded parts.
static func mod(ups: Variant, which: String, key: String) -> float:
	if not ups is Dictionary or not (ups as Dictionary).get(which) is Dictionary:
		return 0.0
	var total := 0.0
	var levels: Dictionary = ups[which]
	for id in levels:
		var l := int(levels[id])
		if l <= 0 or str(id).get_slice(":", 1) != key:
			continue
		var st := find(which, str(id))
		if st.is_empty():
			continue
		total += float(st["per"]) * l
	return total


## Every upgraded stat's total ({key: value}) - for the automaton's gear effects.
static func effects(ups: Variant, which: String) -> Dictionary:
	var out := {}
	for st in list(which):
		if level(ups, which, st["id"]) > 0:
			out[st["key"]] = mod(ups, which, st["key"])
	return out


## A value of a stat in words ("+6%", "-0.6 s", "+30").
static func words(st: Dictionary, v: float) -> String:
	match str(st["fmt"]):
		"%": return "%+d%%" % roundi(v * 100.0)
		"-%": return "%d%%" % roundi(v * 100.0)
		"s": return "%+.1f s" % v
		"+/s": return "%+.2f /s" % v
		"lvl": return "level %d%s" % [roundi(v), " - flies to space" if roundi(v) >= MAX_LEVEL else ""]
		"slot": return "%+d slot%s" % [roundi(v / Shipyard.RACK_UNITS_PER_SLOT), "" if roundi(v / Shipyard.RACK_UNITS_PER_SLOT) == 1 else "s"]
	return "%+d" % roundi(v)


## A shot's damage with a chance of a critical hit (`crit_chance` / `crit_mult` added to the base). [damage, critical?]
static func crit(dmg: float, chance_add: float, mult_add: float) -> Array:
	if randf() < CRIT_BASE + chance_add:
		return [dmg * (CRIT_MULT + mult_add), true]
	return [dmg, false]
