class_name Shipyard
## Ships you can fly and the modules you can fit (inspired by the shipyard /
## outfitting loop of space sims): every class has its own hull, shields,
## speed, cargo hold and slots - weapon hardpoints, internal slots and
## utility mounts. Modules come in ratings E (cheap) to A (best).
##
## Hardpoints hold the weapons (laser, plasma cannon, missile launcher);
## utility mounts hold the active systems (afterburner, shield booster) and
## passive amplifiers; internal slots hold the stat modules below. Module
## effects use the same keys as the tech tree, so they stack with it.

const RATINGS := ["E", "D", "C", "B", "A"]
const RATING_MULT := [1.0, 1.3, 1.65, 2.05, 2.5]
const RATING_PRICE := [1.0, 2.4, 5.5, 12.0, 26.0]

## module id -> slot, name, base price, effect per rating step (times RATING_MULT).
const MODULES := {
	"shield_generator": {"slot": "internal", "name": "Shield Generator", "price": 600, "effects": {"max_shields": 30.0},
		"desc": "Extra shield capacity."},
	"hull_reinforcement": {"slot": "internal", "name": "Hull Reinforcement", "price": 500, "effects": {"max_hull": 35.0},
		"desc": "Bulkheads and armour plating: more hull."},
	"cargo_rack": {"slot": "internal", "name": "Cargo Rack", "price": 350, "effects": {"cargo": 40.0},
		"desc": "More room for trade goods."},
	"thruster_upgrade": {"slot": "internal", "name": "Enhanced Thrusters", "price": 900, "effects": {"speed_mult": 0.06, "handling_mult": 0.06},
		"desc": "Faster and more agile."},
	"shield_cell_bank": {"slot": "internal", "name": "Shield Cell Bank", "price": 700, "effects": {"shield_regen_mult": 0.25},
		"desc": "Shields recharge faster."},
	"gimbal_mounts": {"slot": "internal", "name": "Gimballed Mounts", "price": 1100, "effects": {"range_mult": 0.06, "damage_mult": 0.04},
		"desc": "Weapons track better: more range and damage."},
	"heat_amplifier": {"slot": "utility", "name": "Shield Amplifier", "price": 800, "effects": {"max_shields": 18.0, "shield_regen_mult": 0.08},
		"desc": "Utility mount: boosts shield strength."},
	# Weapon modifiers, resistances and passives (2026-11-11: modules are gear -
	# items you buy, loot and fit; see Gear).
	"focusing_lens": {"slot": "internal", "name": "Focusing Lens", "price": 700, "effects": {"damage_mult": 0.05},
		"desc": "Weapon modifier: every weapon hits harder."},
	"capacitor_bank": {"slot": "internal", "name": "Capacitor Bank", "price": 750, "effects": {"fire_rate_mult": -0.04},
		"desc": "Weapon modifier: every weapon fires faster."},
	"targeting_computer": {"slot": "internal", "name": "Targeting Computer", "price": 650, "effects": {"range_mult": 0.07},
		"desc": "Weapon modifier: every weapon reaches further."},
	"ablative_plating": {"slot": "internal", "name": "Ablative Plating", "price": 600, "effects": {"resist_energy": 0.06, "max_hull": 10.0},
		"desc": "Resistance: lasers and beams do less."},
	"reactive_armour": {"slot": "internal", "name": "Reactive Armour", "price": 650, "effects": {"resist_kinetic": 0.05, "resist_explosive": 0.05},
		"desc": "Resistance: rams, bites and missiles do less."},
	"heat_shield": {"slot": "utility", "name": "Heat Shield", "price": 550, "effects": {"resist_heat": 0.07},
		"desc": "Resistance: plasma and fire do less."},
	"cryo_baffles": {"slot": "utility", "name": "Cryo Baffles", "price": 550, "effects": {"resist_cold": 0.07},
		"desc": "Resistance: frost does less."},
	"fuel_tank": {"slot": "internal", "name": "Fuel Tank", "price": 450, "effects": {"fuel_capacity": 30.0},
		"desc": "A bigger tank: more jumps between refuels."},
	"faraday_mesh": {"slot": "internal", "name": "Faraday Mesh", "price": 600, "effects": {"resist_electric": 0.08},
		"desc": "A conductive mesh round the hull: electric resistance (Electro weapons)."},
	"nanite_repair": {"slot": "utility", "name": "Nanite Repair", "price": 900, "effects": {"hull_regen": 0.5},
		"desc": "Passive: the hull mends itself, slowly."},
}

## Weapons for hardpoints and actives for utility mounts (Items.EQUIPMENT ids).
const HARDPOINT_GEAR := ["laser", "plasma_cannon", "missile_launcher", "electro", "bouncer", "beam"]
const UTILITY_GEAR := ["afterburner", "shield_booster", "star_energizer", "salvage_rig", "cloak", "projection_array", "probe_scanner", "refinery", "fabricator"]

## The fuel tank by hull class (Fuel Tanks add to it): a gate jump costs
## FUEL_JUMP, flying a trickle (FUEL_FLIGHT a second under way).
const CLASS_FUEL := {"interceptor": 60.0, "fighter": 80.0, "gunship": 90.0, "courier": 130.0,
	"explorer": 170.0, "frigate": 140.0, "freighter": 120.0, "cruiser": 180.0, "battleship": 220.0, "dreadnought": 260.0}
const STARTER_FUEL := 100.0
const FUEL_JUMP := 10.0
const FUEL_FLIGHT := 0.05
## Your ship's shields recharging and its hull mending themselves burn fuel:
## this much a point (a full 100-point shield: 2 fuel; 100 hull: 5). Out of
## fuel, neither comes back on its own (Ship._regen_fuel).
const FUEL_PER_SHIELD := 0.02
const FUEL_PER_HULL := 0.05
## A tank unit's price at a station: its market price of a unit of fuel (cargo) over this.
const FUEL_UNITS_PER_CARGO := 10.0

## Slots / hold / handling per hull class (designs' "class" field).
## Cargo hold sizes in inventory slots (Inventory: up to 100 of an item per
## slot) by class, between Inventory.PLAYER_SLOTS (12: never less than you
## carry on foot) and Inventory.SHIP_SLOTS (120: the freighter's). The small
## ships have far fewer. (Prices still go by CLASS_SLOTS.)
const CLASS_HOLD := {
	"interceptor": 12, "fighter": 16, "gunship": 20, "courier": 24,
	"explorer": 40, "frigate": 60, "freighter": 120, "cruiser": 70, "battleship": 80, "dreadnought": 90,
}
const STARTER_HOLD := 16
## Slots a Cargo Rack's "cargo" effect is worth: one per this many.
const RACK_UNITS_PER_SLOT := 4.0

## Slots per hull class: [hardpoints, internal, utility, (unused)] - never
## fewer than the starting Atrapos (3 / 3 / 2) where the class is meant to be
## strong; the top third of a class (grade) gets one more internal slot. The
## hardpoints and their sizes: Hardpoints.LAYOUT (the first number is its count).
const CLASS_SLOTS := {
	"interceptor": [2, 3, 2, 4], "fighter": [3, 3, 2, 8], "courier": [2, 4, 2, 16], "explorer": [2, 5, 3, 20],
	"gunship": [4, 4, 3, 12], "freighter": [2, 7, 2, 110], "frigate": [10, 6, 3, 32],
	"cruiser": [14, 7, 4, 60], "battleship": [18, 8, 4, 80], "dreadnought": [24, 9, 5, 100],
}

## A class's cheapest design: [hull, shields, speed]. Each is already a step up
## from the Atrapos (100 / 100 / 420) where the class is strong; the dearer
## designs of a class (their grade) are better still - up to GRADE_HULL times
## the hull and shields and GRADE_SPEED times the speed.
const CLASS_BASE := {
	"interceptor": [110.0, 100.0, 520.0], "fighter": [150.0, 130.0, 460.0], "courier": [140.0, 130.0, 490.0],
	"explorer": [210.0, 210.0, 400.0], "gunship": [360.0, 260.0, 320.0], "freighter": [380.0, 160.0, 250.0],
	"frigate": [700.0, 480.0, 240.0],
	"cruiser": [1100.0, 800.0, 200.0], "battleship": [1800.0, 1300.0, 170.0], "dreadnought": [2800.0, 2000.0, 140.0],
}
const GRADE_HULL := 2.0
const GRADE_SPEED := 1.15
## Each empire's yards build to their own taste: [hull, shields, speed].
const EMPIRE_TASTE := {
	"sparta": [1.15, 0.95, 0.97], "athens": [1.0, 1.12, 1.0], "ionia": [0.95, 1.05, 1.06],
	"cyclades": [0.95, 1.0, 1.06], "mycenae": [1.1, 1.0, 0.97], "minoa": [1.0, 1.0, 1.02],
}
## A ship's price from what it gives (value(): hull, shields, slots, hold,
## speed), on a steep curve: the weakest ship you can buy costs MIN_PRICE, the
## strongest TOP_PRICE, and in between the price multiplies with every step up
## (value ^ PRICE_POWER) - a better ship is always a real upgrade, and the
## best are a fortune to save for.
const MIN_PRICE := 15000.0
const TOP_PRICE := 3000000.0
static var _value_range := Vector2.ZERO   # (the weakest and strongest designs' values)
static var _power := 0.0

## A design's grade in its class, 0 (the class's cheapest) to 1 (its dearest):
## its listed price's place among the class's designs.
static var _grades := {}

static func grade(class_id: String) -> float:
	if _grades.is_empty():
		var by_class := {}
		for id in ShipDesigns.ids():
			var t: Dictionary = EnemyTypes.get_type(id)
			by_class.get_or_add(str(t.get("class", "fighter")), []).append([float(t.get("price", 0.0)), id])
		for c in by_class:
			var l: Array = by_class[c]
			l.sort()
			for i in l.size():
				_grades[l[i][1]] = float(i) / maxf(1.0, l.size() - 1.0)
	return float(_grades.get(class_id, 0.0))


## What a ship gives, in one number (a straight sum - price_of bends it).
## Its hardpoints count by size (`hp`: their sizes, Hardpoints.LAYOUT): an S
## one 2500, each size up 1.6x.
static func value(hull: float, shields: float, speed: float, cargo: int, slots: Array, hp: Array = []) -> float:
	var guns: float = slots[0] * 2500.0
	if not hp.is_empty():
		guns = 0.0
		for z in hp:
			guns += 2500.0 * pow(1.6, int(z) - Hardpoints.BASE)
	return (hull + 1.2 * shields) * 40.0 + guns + slots[1] * 1500.0 + slots[2] * 1500.0 \
		+ cargo * 50.0 + maxf(0.0, speed - 400.0) * 30.0


## What a ship of these stats costs (see MIN_PRICE).
static func price_of(hull: float, shields: float, speed: float, cargo: int, slots: Array, hp: Array = []) -> int:
	if _power == 0.0:
		var lo := INF
		var hi := 0.0
		for id in ShipDesigns.ids():
			if EnemyTypes.get_type(id).get("capital", false):
				continue   # (the capital ships go past TOP_PRICE: the curve carries on)
			var v := float(_raw(id)["value"])
			lo = minf(lo, v)
			hi = maxf(hi, v)
		_value_range = Vector2(lo, hi)
		_power = log(TOP_PRICE / MIN_PRICE) / log(hi / lo) if hi > lo else 1.0
	var v := value(hull, shields, speed, cargo, slots, hp)
	var p := MIN_PRICE * pow(v / _value_range.x, _power)
	var step := 100 if p < 100000.0 else 5000
	return snappedi(int(p), step)


## Stats of a player-flyable class: {name, hull, shields, speed, cargo,
## hardpoints, internal, utility, price, length, empire, grade}.
static func stats(class_id: String) -> Dictionary:
	var st := _raw(class_id)
	st["price"] = price_of(st["hull"], st["shields"], st["speed"], st["cargo"], [st["hardpoints"], st["internal"], st["utility"]], Hardpoints.layout(class_id))
	return st


## stats() without the price.
static func _raw(class_id: String) -> Dictionary:
	if class_id == "" or class_id == "player":
		var s0 := [3, 3, 2]
		return {"name": "Atrapos-class Light Fighter", "hull": 100.0, "shields": 100.0, "speed": 420.0, "cargo": STARTER_HOLD,
			"hardpoints": 3, "internal": 3, "utility": 2, "value": value(100.0, 100.0, 420.0, STARTER_HOLD, s0),
			"length": 132.0, "empire": Galaxy.HOME_EMPIRE, "grade": 0.0}
	var t: Dictionary = EnemyTypes.get_type(class_id)
	var cls := str(t.get("class", "fighter"))
	var base: Array = CLASS_BASE.get(cls, CLASS_BASE["fighter"])
	var g := grade(class_id)
	var taste: Array = EMPIRE_TASTE.get(str(t.get("empire_style", "")), [1.0, 1.0, 1.0])
	var hull := roundf(base[0] * lerpf(1.0, GRADE_HULL, g) * taste[0])
	var shields := roundf(base[1] * lerpf(1.0, GRADE_HULL, g) * taste[1])
	var speed := roundf(clampf(base[2] * lerpf(1.0, GRADE_SPEED, g) * taste[2], 140.0, 600.0))
	var slots: Array = CLASS_SLOTS.get(cls, CLASS_SLOTS["fighter"]).duplicate()
	if g >= 0.66:
		slots[1] += 1
	var hp: Array = Hardpoints.LAYOUT.get(cls, Hardpoints.LAYOUT["fighter"])
	slots[0] = hp.size()
	var cargo := int(CLASS_HOLD.get(cls, 16))
	return {"name": t["name"], "hull": hull, "shields": shields, "speed": speed, "cargo": cargo,
		"hardpoints": slots[0], "internal": slots[1], "utility": slots[2],
		"value": value(hull, shields, speed, cargo, slots, hp),
		"length": clampf(t["length"] * 0.9, 110.0, 520.0 if t.get("capital", false) else 300.0), "empire": t.get("empire_style", ""), "grade": g}


## Ships a station's shipyard sells: its empire's designs.
static func for_sale(empire: String) -> Array:
	var own := []
	var indie := []
	for id in ShipDesigns.ids():
		var e: String = ShipDesigns.types()[id]["empire_style"]
		if e == empire:
			own.append(id)
		elif e == "":
			indie.append(id)   # independent designs: sold at every shipyard
	if empire == Galaxy.HOME_EMPIRE:
		own.push_front("player")
	return own + indie


## What the shipyard gives for your ship when you buy another: 80% of what
## you paid for it (PlayerData.ship_value).
static func trade_in(data: Node) -> int:
	return roundi(int(data.ship_value) * 0.8)


## The ship's fuel tank: its class's, and Fuel Tanks'.
static func fuel_capacity(data: Node) -> float:
	var cls: String = data.ship_class
	var base := STARTER_FUEL
	if cls != "" and cls != "player":
		base = float(CLASS_FUEL.get(EnemyTypes.get_type(cls).get("class", "fighter"), 80.0))
	return base + module_effect(data, "fuel_capacity") + Upgrades.mod(data.get("upgrades"), data.condition, "ship", "fuel_capacity")


## A tank unit's price at a station (its fuel price, a tenth of a cargo unit).
static func fuel_unit_price(station_id: String) -> float:
	var p := 20.0
	if station_id != "" and Galaxy.stations.has(station_id):
		p = float(Galaxy.buy_price(station_id, "fuel"))
	return maxf(0.5, p / FUEL_UNITS_PER_CARGO)


static func module_price(id: String, rating: int) -> int:
	return roundi(MODULES[id]["price"] * RATING_PRICE[rating])


static func module_name(m: Dictionary) -> String:
	return "%s %s" % [MODULES[m["id"]]["name"], RATINGS[m["rating"]]]


## Summed effects of the fitted modules (same keys as Tech effects).
static func module_effect(data: Node, key: String) -> float:
	var total := 0.0
	for m in data.modules:
		var e: Dictionary = MODULES[m["id"]]["effects"]
		total += e.get(key, 0.0) * RATING_MULT[m["rating"]]
	return total


## The hold's size in slots: the class's, Cargo Racks' extra - from
## Inventory.PLAYER_SLOTS to Inventory.SHIP_SLOTS.
static func cargo_capacity(data: Node) -> int:
	return clampi(int(stats(data.ship_class)["cargo"]) + int((module_effect(data, "cargo") + Upgrades.mod(data.get("upgrades"), data.condition, "ship", "cargo")) / RACK_UNITS_PER_SLOT),
		Inventory.PLAYER_SLOTS, Inventory.SHIP_SLOTS)


static func used_slots(data: Node, slot: String) -> int:
	match slot:
		"hardpoints":
			return Hardpoints.fitted(data).filter(func(w): return w != "").size()
		"utility":
			return UTILITY_GEAR.filter(func(g): return data.has_equipment(g)).size() + data.modules.filter(func(m): return MODULES[m["id"]]["slot"] == "utility").size()
		_:
			return data.modules.filter(func(m): return MODULES[m["id"]]["slot"] == "internal").size()


# --- Areas (the equipment screen: ShipDoll) --------------------------------------------------
# A ship's fittings belong to its areas, like a body's: weapons on the WINGS
# (its hardpoints), weapon modifiers and sensors in the NOSE, armour, shields
# and repair systems in the HULL, the drive's modules at the THRUSTERS, racks,
# tanks and the salvage rig in the cargo BAY. Each area has room for so many
# (area_capacity - from the class's hardpoint / internal / utility counts).

const AREAS := ["nose", "wings", "hull", "thrusters", "bay"]
const AREA_NAMES := {"nose": "Nose", "wings": "Wings", "hull": "Hull", "thrusters": "Thrusters", "bay": "Cargo bay"}
const AREA_OF := {
	"laser": "wings", "plasma_cannon": "wings", "missile_launcher": "wings", "electro": "wings", "bouncer": "wings", "beam": "wings",
	"focusing_lens": "nose", "capacitor_bank": "nose", "targeting_computer": "nose", "gimbal_mounts": "nose",
	"shield_generator": "hull", "hull_reinforcement": "hull", "shield_cell_bank": "hull", "heat_amplifier": "hull",
	"ablative_plating": "hull", "reactive_armour": "hull", "faraday_mesh": "hull", "heat_shield": "hull",
	"cryo_baffles": "hull", "nanite_repair": "hull", "shield_booster": "hull",
	"cloak": "hull", "projection_array": "nose", "thruster_upgrade": "thrusters", "afterburner": "thrusters", "star_energizer": "thrusters",
	"cargo_rack": "bay", "fuel_tank": "bay", "salvage_rig": "bay", "probe_scanner": "nose", "refinery": "bay", "fabricator": "hull",
}


## The area a module / equipment / ship gear item (gear:<module>:<q>) goes in.
static func area_of(id: String) -> String:
	if Hardpoints.is_weapon(id):
		return "wings"
	if Gear.is_gear(id):
		var p := Gear.parse(id)
		id = p[0] if not p.is_empty() else id
	return str(AREA_OF.get(id, "hull"))


## How many fittings an area of this ship takes.
static func area_capacity(data: Node, area: String) -> int:
	var cls := stats(data.ship_class)
	var h := int(cls["hardpoints"])
	var i := int(cls["internal"])
	var u := int(cls["utility"])
	match area:
		"wings":
			return h
		"nose":
			return 1 if i <= 3 else 2
		"hull":
			return maxi(1, i - 1)
		"thrusters":
			return maxi(1, u)
		"bay":
			return 1 if i <= 3 else 2
	return 0


## What's fitted in an area: [{id, kind ("equipment" / "module"), index (modules)}].
static func area_fittings(data: Node, area: String) -> Array:
	var out := []
	if area == "wings":
		var ws := Hardpoints.fitted(data)
		for i in ws.size():
			if ws[i] != "":
				out.append({"id": ws[i], "kind": "weapon", "index": i})
	for g in UTILITY_GEAR:
		if data.has_equipment(g) and area_of(g) == area:
			out.append({"id": g, "kind": "equipment"})
	for k in data.modules.size():
		var m: Dictionary = data.modules[k]
		if area_of(m["id"]) == area:
			out.append({"id": m["id"], "rating": int(m["rating"]), "kind": "module", "index": k})
	return out


## Room left for `id` (an equipment, a module or a ship gear item) in its area.
static func free_for(data: Node, id: String) -> int:
	var a := area_of(id)
	return area_capacity(data, a) - area_fittings(data, a).size()


static func free_slots(data: Node, slot: String) -> int:
	return int(stats(data.ship_class)[slot]) - used_slots(data, slot)
