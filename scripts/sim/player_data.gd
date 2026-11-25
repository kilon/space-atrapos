extends Node
## The player's credits, cargo/consumables and installed equipment.
## Lives in the game scene (so a new game starts fresh) and is saved with it.

signal changed

const START_CREDITS := 150
const START_ITEMS := {"energy_drink": 3}
## What the ship you start with counts as on a trade-in (it was given to you,
## so it's worth what a used light fighter fetches - not the shipyard's price
## for a new Atrapos-class).
const START_SHIP_VALUE := 2500
## Items that are gone (the repair system's: its kits, spare parts and scanners) -
## an older save's are dropped on loading, off its toolbars and layouts too.
const RETIRED_ITEMS := ["repair_kit", "spare_circuit", "spare_conduit", "spare_servo", "spare_plate", "spare_lens",
	"spare_cell", "scanner_mk2", "scanner_mk3"]

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
## (Older saves' on-foot pack - merged into `items` on load: one inventory now. Kept empty.)
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
## flying burn it; stations refuel it (the Workshop), fuel in the hold can
## be pumped in, and a Star Energizer drains a star's power into it. -1: full
## (a new game / an older save).
var fuel := -1.0


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


## Sum of a modifier over the ship's fitted modules and its upgrades.
func mod(key: String) -> float:
	return Shipyard.module_effect(self, key) + Upgrades.mod(upgrades, "ship", key)


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
	var frags := items.keys().filter(func(id): return Mining.is_frag(str(id)) and count(id) > 0 and Mining.valid(str(id)))   # (mining's fragments)
	frags.sort()
	return out + gear + reports + frags


func _look_json() -> Dictionary:
	var out := {}
	for k in ship_look:
		out[k] = ship_look[k].to_html() if ship_look[k] is Color else ship_look[k]
	return out


func get_save_data() -> Dictionary:
	return {"credits": credits, "items": items, "equipment": equipment.keys(), "weapons": weapons, "weapons_off": weapons_off.keys(),
		"ship_class": ship_class, "ship_value": ship_value, "modules": modules, "ship_look": _look_json(), "owned_parts": owned_parts,
		"discovered": discovered.keys(), "lost": lost, "carried": carried,
		"toolbar": toolbar, "toolbar_foot": toolbar_foot, "layout_hold": layout_hold, "layout_carried": layout_carried, "loadout": loadout,
		"fuel": fuel, "stamina": stamina, "skills": skills, "upgrades": upgrades, "industry": industry}


func load_save_data(data: Dictionary) -> void:
	credits = int(data.get("credits", START_CREDITS))
	fuel = float(data.get("fuel", -1.0))
	stamina = Stamina.of(data)
	skills = Skills.clean(data.get("skills"))
	# (an older save's "condition" - the parts' faults of the repair system that's gone - isn't read)
	industry = {}
	var ind = data.get("industry", {})
	if ind is Dictionary and ind.get("queue") is Array:
		industry["queue"] = []
		for j in ind["queue"]:
			if j is Dictionary and str(j.get("kind", "")) in ["refine", "fab"] and (j["kind"] != "fab" or Industry.RECIPES.has(str(j.get("id", "")))):   # (a recipe that's gone: dropped)
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
	var keep := func(x): return "" if x == null or _retired(str(x)) else str(x)
	toolbar = Inventory.toolbar(d, false).map(keep)
	toolbar_foot = Inventory.toolbar(d, true).map(keep)
	layout_hold = Array(d.get("layout_hold", [])).map(keep)
	layout_carried = Array(d.get("layout_carried", [])).map(keep)
	lost = []
	for e in data.get("lost", []):
		if not _retired(str(e["id"])):
			lost.append({"kind": str(e["kind"]), "id": str(e["id"]), "n": int(e["n"])})
	items = {}
	var saved_items: Dictionary = data.get("items", START_ITEMS)
	for id in saved_items:
		if not _retired(str(id)):
			items[id] = int(saved_items[id])  # JSON numbers load as floats
	for id in carried:   # (one inventory now: an older save's on-foot pack merges into it)
		if not _retired(str(id)):
			items[id] = int(items.get(id, 0)) + int(carried[id])
	carried = {}
	layout_carried = []
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
		if Shipyard.MODULES.has(str(m["id"])):   # (an older save's Nanite Repair: gone)
			modules.append({"id": m["id"], "rating": int(m["rating"])})
	# (an older save's "tech": the tech tree's gone - its research no longer counts)
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


## An item of an older save's that's gone (RETIRED_ITEMS, or gear of a ship module that's gone).
static func _retired(id: String) -> bool:
	return id in RETIRED_ITEMS or (Gear.is_gear(id) and Gear.parse(id).is_empty())
