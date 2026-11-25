extends Node
## The player's credits, cargo/consumables and installed equipment.
## Lives in the game scene (so a new game starts fresh) and is saved with it.

signal changed

const START_CREDITS := 150
const START_ITEMS := {"repair_kit": 2, "energy_drink": 3}
## What the ship you start with counts as on a trade-in (it was given to you,
## so it's worth what a used light fighter fetches - not the shipyard's price
## for a new Atrapos-class).
const START_SHIP_VALUE := 2500

var credits := START_CREDITS
var items: Dictionary = START_ITEMS.duplicate()
var equipment: Dictionary = {}   # systems and other fittings owned (weapons: `weapons`)
## The weapons on the ship's hardpoints (Hardpoints: an item id or "" each,
## one a hardpoint of the class) and the kinds switched off on the toolbar.
var weapons: Array = Hardpoints.START.duplicate()
var weapons_off: Dictionary = {}
## Component upgrades (Upgrades): {"ship": {"<part>:<stat>": level}, "automaton": {...}}.
var upgrades: Dictionary = {}
## The ship's industry at work (Industry: the refinery's and fabricator's queue).
var industry: Dictionary = {}
var _ind_rng := RandomNumberGenerator.new()
var tech: Dictionary = {}  # unlocked tech ids
## The ship you fly ("player" = the Atrapos-class fighter; else a design id)
## and its fitted modules [{id, rating}] (see Shipyard).
var ship_class := "player"
## What your ship is worth on a trade-in (Shipyard.trade_in): what you paid
## for it, or START_SHIP_VALUE for the one you started with.
var ship_value := START_SHIP_VALUE
var modules: Array = []
## Ship Designer: the look (ShipParts spec overrides) and bought parts / skins.
var ship_look: Dictionary = {}
var owned_parts: Array = []
## What you've discovered, for the Encyclopedia (Discovery: "ship:<id>" ...).
var discovered: Dictionary = {}
## What you lost dying and may win back (LostItems): [{kind, id, n}].
var lost: Array = []
## What you carry on foot (Inventory.carried: 12 slots, moved to and from the ship at it).
var carried: Dictionary = {}
## The automaton's stamina on foot (Stamina).
var stamina := Stamina.MAX
## Its skills: level, experience, points, ranks (Skills).
var skills: Dictionary = {}
## The toolbars (Inventory.toolbar): 9 slots each, in space and on foot.
var toolbar: Array = Inventory.SHIP_TOOLBAR.duplicate()
var toolbar_foot: Array = Inventory.FOOT_TOOLBAR.duplicate()
## Where things sit in the hold and in what you carry (Inventory.slots: dragged there).
var layout_hold: Array = []
var layout_carried: Array = []
## The automaton's loadout on foot (Gear.LOADOUT slots -> gear item ids).
var loadout: Dictionary = Gear.DEFAULT_LOADOUT.duplicate()


## The industry works on as you fly (Industry.tick) - a few times a second.
var _ind_t := 0.0

func _process(delta: float) -> void:
	_ind_t += delta
	if _ind_t < 0.25:
		return
	if industry.get("queue") is Array and not industry["queue"].is_empty():
		var made := Industry.tick(self, _ind_t, _ind_rng)
		if not made.is_empty() and industry["queue"].is_empty():
			GameLog.post("The industry's queue is done.", "good")
	_ind_t = 0.0


func _ready() -> void:
	_ind_rng.randomize()
	add_to_group("player_data")
	for id in items:
		discovered["item:" + id] = true
	for id in equipment:
		discovered["gear:" + id] = true
	for id in weapons:
		if id != "":
			discovered["gear:" + Hardpoints.kind(id)] = true


func count(id: String) -> int:
	return items.get(id, 0)


func add_item(id: String, amount := 1) -> void:
	if id == "credits":
		add_credits(amount)
		return
	items[id] = count(id) + amount
	discovered["item:" + id] = true
	changed.emit()


func remove_item(id: String, amount := 1) -> bool:
	if count(id) < amount:
		return false
	items[id] = count(id) - amount
	if items[id] <= 0:
		items.erase(id)
	changed.emit()
	return true


## Room left in the hold: empty slots' worth of items (Inventory; credits take no room).
func cargo_free() -> int:
	return maxi(0, Shipyard.cargo_capacity(self) - Galaxy.cargo_used(self)) * Inventory.STACK


## How many more of `id` the hold takes (its last stack's room too).
func room_for(id: String) -> int:
	return Inventory.room_for(items, id, Shipyard.cargo_capacity(self))


func add_credits(amount: int) -> void:
	credits += amount
	changed.emit()


func spend(amount: int) -> bool:
	if credits < amount:
		return false
	credits -= amount
	changed.emit()
	return true


## A kill's chance to win a lost thing back (LostItems.regain, on this data):
## its name, or "".
func regain_lost(roll := -1.0) -> String:
	var d := {"items": items, "equipment": equipment.keys(), "lost": lost}
	var got := LostItems.regain(d, roll)
	if got != "":
		items = d["items"]
		for id in d["equipment"]:
			if Items.WEAPONS.has(id):
				add_equipment(id)   # (an older save's lost weapon kind: back as a weapon - fitted, or into the hold)
			else:
				equipment[id] = true
		changed.emit()
	return got


# --- Fuel ------------------------------------------------------------------------------------
## The ship's fuel tank (Shipyard.fuel_capacity): jumps through gates and
## flying burn it; stations refuel it (the Repair tab), fuel in the hold can
## be pumped in, and a Star Energizer drains a star's power into it. -1: full
## (a new game / an older save).
var fuel := -1.0
## The damage to your ship's and automaton's parts (Parts: faults, found or not).
var condition: Dictionary = {}


func fuel_max() -> float:
	return Shipyard.fuel_capacity(self)


func fuel_level() -> float:
	return fuel_max() if fuel < 0.0 else minf(fuel, fuel_max())


## Burns `n` fuel; false (and nothing burnt) if there isn't that much.
func use_fuel(n: float) -> bool:
	var f := fuel_level()
	if f < n - 0.001:
		return false
	fuel = f - n
	return true


## Burns up to `n` (flying: what's left, if less).
func drain_fuel(n: float) -> void:
	fuel = maxf(0.0, fuel_level() - n)


func add_fuel(n: float) -> void:
	fuel = minf(fuel_max(), fuel_level() + n)
	changed.emit()


func has_equipment(id: String) -> bool:
	if Items.WEAPONS.has(id):
		return Hardpoints.has_kind(self, id)   # (a weapon: one fitted)
	return equipment.get(id, false)


func add_equipment(id: String) -> void:
	if Items.WEAPONS.has(id):
		# A weapon kind: one of it, as big as a free hardpoint takes - fitted
		# there, or (none free) into the hold.
		var lay := Hardpoints.layout(ship_class)
		var r: Array = Hardpoints.MADE_IN[id]
		var best := -1
		var ws := Hardpoints.fitted(self)
		for i in lay.size():
			if ws[i] == "" and int(lay[i]) >= int(r[0]) and (best < 0 or lay[i] > lay[best]):
				best = i
		var size: int = clampi(int(lay[best]) if best >= 0 else Hardpoints.BASE, int(r[0]), int(r[1]))
		var wid := Hardpoints.item_id(id, size)
		if best >= 0:
			Hardpoints.fit(self, wid, best, false)
		else:
			Inventory.add(items, wid, 1, Shipyard.cargo_capacity(self))
			discovered["gear:" + id] = true
			changed.emit()
		return
	equipment[id] = true
	discovered["gear:" + id] = true
	# A new weapon or system goes on the toolbar's first free slot.
	if (Items.WEAPONS.has(id) or Items.SYSTEMS.has(id)) and not id in toolbar:
		var free := toolbar.find("")
		if free >= 0:
			toolbar[free] = id
	changed.emit()


# --- Tech -----------------------------------------------------------------------

func has_tech(id: String) -> bool:
	return tech.get(id, false)


## "owned", "available" (prerequisite met) or "locked".
func tech_state(id: String) -> String:
	if has_tech(id):
		return "owned"
	var pre := Tech.prerequisite(id)
	return "available" if pre == "" or has_tech(pre) else "locked"


func can_afford_tech(id: String) -> bool:
	var t: Dictionary = Tech.TECHS[id]
	return credits >= t["cost"] and count("data_core") >= t["cores"]


func unlock_tech(id: String) -> bool:
	if tech_state(id) != "available" or not can_afford_tech(id):
		return false
	var t: Dictionary = Tech.TECHS[id]
	credits -= t["cost"]
	if t["cores"] > 0:
		remove_item("data_core", t["cores"])
	tech[id] = true
	GameLog.post("Researched: %s (%s)" % [t["name"], t["short"]], "good")
	changed.emit()
	return true


## Sum of a modifier over all unlocked techs (see tech.gd for keys).
func mod(key: String) -> float:
	var total := 0.0
	for id in tech:
		total += Tech.TECHS[id]["effects"].get(key, 0.0)
	return total + Shipyard.module_effect(self, key) + Parts.mod(condition, "ship", key) + Upgrades.mod(upgrades, condition, "ship", key)


## Item ids currently held, in catalogue order (then gear, by name).
func held_items() -> Array:
	var out := []
	for id in Items.ITEMS:
		if count(id) > 0:
			out.append(id)
	var gear := items.keys().filter(func(id): return Gear.is_gear(str(id)) and count(id) > 0 and Items.exists(id))
	gear.sort()
	var reports := items.keys().filter(func(id): return NavReports.is_report(str(id)) and count(id) > 0 and Items.exists(id))
	reports.sort()
	return out + gear + reports


func _look_json() -> Dictionary:
	var out := {}
	for k in ship_look:
		out[k] = ship_look[k].to_html() if ship_look[k] is Color else ship_look[k]
	return out


func get_save_data() -> Dictionary:
	return {"credits": credits, "items": items, "equipment": equipment.keys(), "weapons": weapons, "weapons_off": weapons_off.keys(), "tech": tech.keys(),
		"ship_class": ship_class, "ship_value": ship_value, "modules": modules, "ship_look": _look_json(), "owned_parts": owned_parts,
		"discovered": discovered.keys(), "lost": lost, "carried": carried,
		"toolbar": toolbar, "toolbar_foot": toolbar_foot, "layout_hold": layout_hold, "layout_carried": layout_carried, "loadout": loadout,
		"fuel": fuel, "stamina": stamina, "skills": skills, "condition": condition, "upgrades": upgrades, "industry": industry}


func load_save_data(data: Dictionary) -> void:
	credits = int(data.get("credits", START_CREDITS))
	fuel = float(data.get("fuel", -1.0))
	stamina = Stamina.of(data)
	skills = Skills.clean(data.get("skills"))
	condition = Parts.load_condition(data.get("condition", {}))
	industry = {}
	var ind = data.get("industry", {})
	if ind is Dictionary and ind.get("queue") is Array:
		industry["queue"] = []
		for j in ind["queue"]:
			if j is Dictionary and str(j.get("kind", "")) in ["refine", "fab"]:
				industry["queue"].append({"kind": str(j["kind"]), "id": str(j["id"]), "n": int(j["n"]), "done": int(j.get("done", 0)), "t": float(j.get("t", 0.0))})
	upgrades = {}
	var ups = data.get("upgrades", {})
	if ups is Dictionary:
		for w in ["ship", "automaton"]:
			if ups.get(w) is Dictionary:
				upgrades[w] = {}
				for id in ups[w]:
					if not Upgrades.find(w, str(id)).is_empty():
						upgrades[w][str(id)] = clampi(int(ups[w][id]), 0, Upgrades.MAX_LEVEL)
	var d := data.duplicate(true)
	loadout = Gear.DEFAULT_LOADOUT.duplicate()
	var lo = d.get("loadout")
	if lo is Dictionary:
		for slot in lo:
			if slot in Gear.LOADOUT and Gear.fits(str(lo[slot]), slot):
				loadout[slot] = str(lo[slot])
	carried = {}
	var saved_carried: Dictionary = Inventory.carried(d)   # (an older save's pack moves in)
	for id in saved_carried:
		carried[id] = int(saved_carried[id])
	toolbar = Inventory.toolbar(d, false).duplicate()
	toolbar_foot = Inventory.toolbar(d, true).duplicate()
	layout_hold = Array(d.get("layout_hold", [])).map(func(x): return str(x) if x != null else "")
	layout_carried = Array(d.get("layout_carried", [])).map(func(x): return str(x) if x != null else "")
	lost = []
	for e in data.get("lost", []):
		lost.append({"kind": str(e["kind"]), "id": str(e["id"]), "n": int(e["n"])})
	items = {}
	var saved_items: Dictionary = data.get("items", START_ITEMS)
	for id in saved_items:
		items[id] = int(saved_items[id])  # JSON numbers load as floats
	equipment = {}
	var old_weapons := []
	for id in data.get("equipment", []):
		if Items.WEAPONS.has(id):
			old_weapons.append(id)   # (an older save: weapon kinds owned, one of each)
		else:
			equipment[id] = true
	ship_class = data.get("ship_class", "player")
	weapons_off = {}
	for k in data.get("weapons_off", []):
		weapons_off[str(k)] = true
	if data.get("weapons") is Array:
		weapons = Array(data["weapons"]).map(func(x): return str(x) if x != null and not Hardpoints.parse(str(x)).is_empty() else "")
		Hardpoints.fitted(self)   # (sized to the class)
	else:
		Hardpoints.from_equipment(self, old_weapons)
	# Older saves: the starting ship at its trade-in value, a bought one at its price.
	ship_value = int(data.get("ship_value", START_SHIP_VALUE if ship_class == "player" else Shipyard.stats(ship_class)["price"]))
	ship_look = data.get("ship_look", {})
	owned_parts = data.get("owned_parts", [])
	modules = []
	for m in data.get("modules", []):
		modules.append({"id": m["id"], "rating": int(m["rating"])})
	tech = {}
	for id in data.get("tech", []):
		if Tech.TECHS.has(id):
			tech[id] = true
	discovered = {}
	for k in data.get("discovered", []):
		discovered[str(k)] = true
	for id in items:   # (older saves: what you hold and fly with, you know)
		discovered["item:" + id] = true
	for id in equipment:
		discovered["gear:" + id] = true
	for id in weapons:
		if id != "":
			discovered["gear:" + Hardpoints.kind(id)] = true
	changed.emit()
