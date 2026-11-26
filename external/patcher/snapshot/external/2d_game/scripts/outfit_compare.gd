class_name OutfitCompare
## Before and after: what fitting (or taking out) a weapon, system or module
## does to your ship, or a piece of gear to your automaton - the outfitter's
## comparison. Each row is [label, before, after, format, higher_is_better]
## (before / after: numbers, or null for "none"); only rows that change.
##
## The "after" is worked out the game's own way: the item is fitted to the
## player's data for a moment (data.modules / equipment / loadout), the stats
## read with the same formulas the ship and the automaton use, then put back.

## The ship's numbers: {key: [label, value, format, higher_is_better]}.
static func ship_stats(data: Node, base: Dictionary) -> Dictionary:
	var cls := Shipyard.stats(data.ship_class)
	var m := func(k: String) -> float: return data.mod(k)
	var out := {
		"hull": ["Hull", float(cls["hull"]) + m.call("max_hull"), "%.0f", true],
		"shields": ["Shields", float(cls["shields"]) + m.call("max_shields"), "%.0f", true],
		"recharge": ["Shield recharge /s", float(base.get("regen", 10.0)) * (1.0 + m.call("shield_regen_mult")), "%.1f", true],
		"repair": ["Hull repair /s", m.call("hull_regen"), "%.1f", true],
		"speed": ["Top speed", float(cls["speed"]) * (1.0 + m.call("speed_mult")), "%.0f", true],
		"handling": ["Handling", 100.0 * (1.0 + m.call("handling_mult")), "%.0f%%", true],
		"damage": ["Weapon damage", 100.0 * (1.0 + m.call("damage_mult")), "%.0f%%", true],
		"rate": ["Fire rate", 100.0 / maxf(0.2, 1.0 + m.call("fire_rate_mult")), "%.0f%%", true],
		"range": ["Weapon range", 100.0 * (1.0 + m.call("range_mult")), "%.0f%%", true],
		"accuracy": ["Accuracy", 100.0 * clampf(Accuracy.BASE_SHIP + m.call("accuracy"), 0.2, 0.99), "%.0f%%", true],
		"evasion": ["Evasion", 100.0 * clampf(m.call("evasion"), 0.0, 0.6), "%.0f%%", true],
		"crit": ["Critical chance", 100.0 * (Upgrades.CRIT_BASE + m.call("crit_chance")), "%.0f%%", true],
		"hold": ["Hold (slots)", float(Shipyard.cargo_capacity(data)), "%.0f", true],
		"fuel": ["Fuel tank", Shipyard.fuel_capacity(data), "%.0f", true],
		"weapons": ["Weapons fitted", float(Shipyard.used_slots(data, "hardpoints")), "%.0f", true],
		"firepower": ["Firepower (damage /s)", firepower(data), "%.0f", true],
	}
	for t in Gear.DAMAGE_TYPES:
		out["res_" + t] = ["%s resistance" % t.capitalize(), 100.0 * clampf(m.call("resist_" + t), 0.0, Gear.RESIST_CAP), "%.0f%%", true]
	return out


## Every fitted ship weapon's damage a second together, with your modifiers
## (they all fire at once: Hardpoints).
static func firepower(data: Node) -> float:
	var total := 0.0
	for id in Hardpoints.fitted(data):
		if id != "":
			total += weapon_dps(data, id)
	return total


## The strongest fitted ship weapon's damage a second.
static func best_dps(data: Node) -> float:
	var best := 0.0
	for id in Hardpoints.fitted(data):
		if id != "":
			best = maxf(best, weapon_dps(data, id))
	return best


## A weapon's damage a second (`id`: a weapon item, or a kind at size S).
static func weapon_dps(data: Node, id: String) -> float:
	var w: Dictionary = Hardpoints.stats(id) if Hardpoints.is_weapon(id) else Items.WEAPONS[id]
	var dmg: float = float(w.get("damage", 0.0)) * (1.0 + data.mod("damage_mult"))
	var interval: float = float(w.get("interval", 1.0)) * maxf(0.2, 1.0 + data.mod("fire_rate_mult"))
	return dmg / maxf(0.01, interval)


## The automaton's numbers from a loadout (as LoadoutPanel.summary works them out).
static func foot_stats(lo: Dictionary) -> Dictionary:
	var w := Gear.weapon_stats(str(lo.get("weapon", Gear.DEFAULT_LOADOUT["weapon"])))
	var fx := Gear.loadout_effects(lo)
	var dmg: float = w["damage"] * (1.0 + float(fx.get("damage_mult", 0.0)))
	var rate: float = 1.0 / (w["interval"] * maxf(0.25, 1.0 + float(fx.get("fire_rate_mult", 0.0))))
	var out := {
		"health": ["Health", 100.0 + float(fx.get("max_hp", 0.0)), "%.0f", true],
		"damage": ["Damage a shot", dmg, "%.0f", true],
		"rate": ["Shots /s", rate, "%.1f", true],
		"dps": ["Damage /s", dmg * rate, "%.0f", true],
		"reach": ["Reach", w["range"] * (1.0 + float(fx.get("range_mult", 0.0))), "%.0f", true],
		"accuracy": ["Accuracy", 100.0 * clampf(Accuracy.BASE_FOOT + float(fx.get("accuracy", 0.0)), 0.2, 0.99), "%.0f%%", true],
		"healing": ["Healing", 100.0 * (1.0 + float(fx.get("regen_mult", 0.0))), "%.0f%%", true],
		"speed": ["Speed", 100.0 * (1.0 + float(fx.get("speed_mult", 0.0))), "%.0f%%", true],
	}
	for t in Gear.DAMAGE_TYPES:
		out["res_" + t] = ["%s resistance" % t.capitalize(), 100.0 * clampf(float(fx.get("resist_" + t, 0.0)), 0.0, Gear.RESIST_CAP), "%.0f%%", true]
	return out


## Rows that differ between two stat tables (same keys).
static func diff(before: Dictionary, after: Dictionary) -> Array:
	var rows := []
	for k in before:
		var a: float = before[k][1]
		var b: float = after[k][1]
		if absf(a - b) > 0.0005 * maxf(1.0, absf(a)):
			rows.append([before[k][0], a, b, before[k][2], before[k][3]])
	return rows


## Fitting `id` to the ship: a module (Shipyard.MODULES id, at `rating`), ship
## gear ("gear:<module>:<q>") or a weapon / system (equipment). `remove`: a
## fitted module's index - the rows are then for taking it out.
## A weapon item (Hardpoints) goes in the best free hardpoint it fits;
## `remove_weapon`: a hardpoint whose weapon is taken out.
static func ship_rows(data: Node, base: Dictionary, id: String, rating := 0, remove := -1, remove_weapon := -1) -> Array:
	var before := ship_stats(data, base)
	var mods: Array = data.modules
	var saved_mods: Array = mods.duplicate(true)
	var saved_eq: Dictionary = data.equipment.duplicate()
	var ws := Hardpoints.fitted(data)
	var saved_ws: Array = ws.duplicate()
	if remove_weapon >= 0 and remove_weapon < ws.size():
		ws[remove_weapon] = ""
	elif Hardpoints.is_weapon(id):
		var slot := Hardpoints.free_slot_for(data, id)
		if slot >= 0:
			ws[slot] = id
	elif remove >= 0 and remove < mods.size():
		mods.remove_at(remove)
	elif Gear.is_gear(id):
		var p := Gear.parse(id)
		if not p.is_empty() and Shipyard.MODULES.has(p[0]):
			mods.append({"id": p[0], "rating": Gear.quality(id)})
	elif Shipyard.MODULES.has(id):
		mods.append({"id": id, "rating": rating})
	elif Items.EQUIPMENT.has(id):
		data.equipment[id] = true
	var after := ship_stats(data, base)
	data.modules.assign(saved_mods)
	data.equipment = saved_eq
	data.weapons.assign(saved_ws)
	return diff(before, after)


## Equipping automaton gear `id` (in the slot it would go in - see
## Gear.slot_for: what's there now is what it replaces).
static func foot_rows(lo: Dictionary, id: String) -> Array:
	var slot := Gear.slot_for(lo, id)
	if slot == "":
		return []
	var after_lo := lo.duplicate()
	after_lo[slot] = id
	return diff(foot_stats(lo), foot_stats(after_lo))


## What a ship weapon is on its own: [label, value, format] rows.
static func weapon_facts(data: Node, id: String) -> Array:
	if not Items.WEAPONS.has(id) and not Hardpoints.is_weapon(id):
		return []
	var w: Dictionary = Hardpoints.stats(id) if Hardpoints.is_weapon(id) else Items.WEAPONS[id]
	var dmg: float = float(w.get("damage", 0.0)) * (1.0 + data.mod("damage_mult"))
	var interval: float = float(w.get("interval", 1.0)) * maxf(0.2, 1.0 + data.mod("fire_rate_mult"))
	return [["Damage a shot", dmg, "%.0f"], ["Shots /s", 1.0 / maxf(0.01, interval), "%.1f"],
		["Range", float(w.get("range", 0.0)) * (1.0 + data.mod("range_mult")), "%.0f"], ["Damage /s", dmg / maxf(0.01, interval), "%.0f"]]


## What a ship system does: [label, value, format] rows.
static func system_facts(id: String) -> Array:
	if not Items.SYSTEMS.has(id):
		return []
	var s: Dictionary = Items.SYSTEMS[id]
	var rows := []
	if s.has("cooldown"):
		rows.append(["Cooldown", float(s["cooldown"]), "%.0f s"])
	if s.has("duration"):
		rows.append(["Lasts", float(s["duration"]), "%.1f s"])
	return rows
