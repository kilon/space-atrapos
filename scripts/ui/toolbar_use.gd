class_name ToolbarUse
extends RefCounted
## What pressing a toolbar slot does in the 3D game (the HUD's toolbar: a
## click, or its 1-9 key), by what's on it (Inventory.toolbar_kind):
##   on foot - a tool: the rifle / mining beam out (the digger put away), the
##     terrain digger out (again: the rifle back), the ground scanner in hand (the left button: its pulse);
##     automaton gear: equipped from what you carry or the hold (a weapon also
##     brought out), already on - the rifle out if it's the weapon; food and
##     energy drinks: stamina back, medicine: health back (one used: what
##     you carry first, then the hold);
##   in the ship - a weapon kind switched on / off (PlayerData.weapons_off);
##     the shield booster tops the shields up (with its cooldown,
##     Items.SYSTEMS); a weapon or ship gear in the hold
##     fitted; fuel pumped into the tank.
## Returns the message to flash ("" - the thing said its own).

## When each system is ready again (Time msec): the shield booster...
static var _ready_at := {}
## The tool in the automaton's hands last picked from the toolbar: the rifle, its mining beam or the scanner
## (the digger's out when the deposits say so - held() asks them).
static var _held := "tool:rifle"


## The tool in the automaton's hands now (its toolbar slot highlighted): the terrain
## digger while it's out, else the rifle or its mining beam, whichever was picked last.
static func held(cosmos: Node) -> String:
	var dep: Node = cosmos.get("deposits") if cosmos else null
	if dep and bool(dep.get("digger")):
		return "tool:digger"
	return _held


static func use(cosmos: Node, data: Node, id: String, foot: bool) -> String:
	if data == null or id == "":
		return ""
	match Inventory.toolbar_kind(id, foot):
		"tool":
			return _tool(cosmos, id)
		"gear":
			return _gear(cosmos, data, id)
		"consumable":
			return _foot_supply(cosmos, data, id) if foot else _fuel(data)
		"skill":
			return Items.display_name(id)
		"weapon":
			return _weapon_kind(data, id)
		"system":
			return _system(cosmos, data, id)
		"weapon_item":
			if data.count(id) <= 0:
				return "No %s in the hold" % Hardpoints.title(id)
			if Hardpoints.fit(data, id):
				_refit(cosmos)
				return "Fitted %s" % Hardpoints.title(id)
			return "No free hardpoint for %s" % Hardpoints.title(id)
		"ship_gear":
			if Inventory.toolbar_equipped(data, id, false) and data.count(id) <= 0:
				return Gear.title(id)
			if Gear.fit(data, id):
				data.changed.emit()
				_refit(cosmos)
				return "Fitted %s" % Gear.title(id)
			return "No room for %s" % Gear.title(id) if data.count(id) > 0 else "No %s in the hold" % Gear.title(id)
	return Items.display_name(id)


## Seconds before system `id` can be used again.
static func cooldown_left(id: String) -> float:
	return maxf(0.0, (float(_ready_at.get(id, 0)) - Time.get_ticks_msec()) / 1000.0)


static func _cool(id: String) -> void:
	_ready_at[id] = Time.get_ticks_msec() + int(float(Items.SYSTEMS[id].get("cooldown", 0.0)) * 1000.0)


# --- On foot ------------------------------------------------------------------------

static func _tool(cosmos: Node, id: String) -> String:
	var dep: Node = cosmos.get("deposits") if cosmos else null
	var w: Node = cosmos.get("walker") if cosmos else null
	match id:
		"tool:digger":
			if w == null or w.get("deck") != null or dep == null:
				return "The digger works out on a world's ground"
			dep.toggle_digger()   # (says "Terrain digger" / "Rifle")
			if not bool(dep.get("digger")):
				_held = "tool:rifle"   # (put away: the rifle back in hand)
			return ""
	_rifle_out(cosmos)
	_held = id   # (the rifle, its mining beam, or the scanner: the left button then sends its pulse)
	return str(Inventory.TOOLS[id]["name"])


## The rifle in the automaton's hands (the digger put away).
static func _rifle_out(cosmos: Node) -> void:
	var dep: Node = cosmos.get("deposits") if cosmos else null
	if dep and bool(dep.get("digger")):
		dep.digger = false
		dep.dig_at = Vector3.ZERO


static func _gear(cosmos: Node, data: Node, id: String) -> String:
	if data.loadout.values().has(id):
		if Gear.slot_of(id) == "weapon":
			_rifle_out(cosmos)
		return Gear.title(id)
	var slot := Gear.slot_for(data.loadout, id)
	var from_carried := int(data.carried.get(id, 0)) > 0
	if slot == "" or (not from_carried and data.count(id) <= 0):
		return "No %s to equip" % Gear.title(id)
	var inv: Dictionary = data.carried if from_carried else data.items
	var cap: int = Inventory.PLAYER_SLOTS if from_carried else Shipyard.cargo_capacity(data)
	if not Gear.equip(data.loadout, inv, cap, id, slot):
		return "No room to take off the %s" % Gear.title(str(data.loadout.get(slot, "")))
	if slot == "weapon":
		_rifle_out(cosmos)
	data.changed.emit()
	return "Equipped %s" % Gear.title(id)


## Food, an energy drink, medicine - one used on foot.
static func _foot_supply(cosmos: Node, data: Node, id: String) -> String:
	var name := Items.display_name(id)
	var inv: Dictionary = data.carried if int(data.carried.get(id, 0)) > 0 else data.items
	if int(inv.get(id, 0)) <= 0:
		return "No %s left" % name
	var w: Node = cosmos.get("walker") if cosmos else null
	var food := Stamina.restores(id)
	if food > 0.0:
		if data.stamina >= Stamina.MAX - 0.5:
			return "Stamina full"
		data.stamina = minf(Stamina.MAX, data.stamina + food)
	else:
		var heal := 60.0
		if w == null or float(w.hp) >= CosmosWalker.MAX_HP - 0.5:
			return "Health full"
		w.hp = minf(CosmosWalker.MAX_HP, float(w.hp) + heal)
	Inventory.take(inv, id, 1)
	data.changed.emit()
	return "%s used" % name


# --- In the ship --------------------------------------------------------------------

static func _weapon_kind(data: Node, id: String) -> String:
	var name: String = Items.WEAPONS[id]["name"]
	if not data.has_equipment(id):
		return "No %s fitted" % name
	if data.weapons_off.has(id):
		data.weapons_off.erase(id)
		return "%s on" % name
	data.weapons_off[id] = true
	return "%s off" % name


static func _system(cosmos: Node, data: Node, id: String) -> String:
	var name: String = Items.SYSTEMS[id]["name"]
	var sys: Dictionary = Items.SYSTEMS[id]
	if sys.has("equipment") and not data.has_equipment(str(sys["equipment"])):
		return "No %s installed" % name
	if cooldown_left(id) > 0.0:
		return "%s recharging" % name
	var ship: Node = cosmos.get("ship") if cosmos else null
	match id:
		"shield_booster":
			if ship:
				ship.shield = minf(ship.max_shield, ship.shield + ship.max_shield * 0.6)
			_cool(id)
			return name
	return name


static func _fuel(data: Node) -> String:
	if data.count("fuel") <= 0:
		return "No fuel in the hold"
	if data.fuel_level() >= data.fuel_max() - 0.5:
		return "Tank full"
	data.remove_item("fuel", 1)
	data.add_fuel(Shipyard.FUEL_UNITS_PER_CARGO)
	return "Fuel %d / %d" % [floori(data.fuel_level()), roundi(data.fuel_max())]


## The ship's numbers again after a fitting changed.
static func _refit(cosmos: Node) -> void:
	var ship: Node = cosmos.get("ship") if cosmos else null
	if ship and ship.has_method("apply_upgrades"):
		ship.apply_upgrades()
