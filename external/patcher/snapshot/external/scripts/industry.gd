class_name Industry
extends RefCounted
## The ship's industry (Ship Computer > INDUSTRY), with the equipment for it:
##  - the REFINERY ("refinery") turns mined fragments (Mining: "frag:<mineral>")
##    into their mineral, a unit each (rubble: scrap, now and then a mineral),
##    REFINE_TIME s a unit (less with the reactor's refinery upgrade);
##  - the FABRICATOR ("fabricator") makes things from minerals and goods
##    (RECIPES): metals and parts for the markets, spare parts for the Repair
##    Bay, missiles and repair kits, small weapons, and UPGRADE KITS;
##  - UPGRADE KITS fit a component upgrade (Upgrades) yourself: a Mk I raises a
##    stat to level 1 or 2, a Mk II to 3 or 4, a Mk III to 5.
## Work goes on in the background while you fly, a unit at a time (tick()): its
## inputs are taken when it's ordered; what's made goes into the hold (it waits
## when the hold is full). The jobs: PlayerData.industry {"queue": [job...]}.
## A job: {kind: "refine"/"fab", id (the fragment / the recipe), n, done, t}.

const REFINE_TIME := 1.2
const KITS := {"upkit_1": [0, 1], "upkit_2": [2, 3], "upkit_3": [4, 4]}   # kit -> the levels it raises from

## id -> [name, category, [output item, count], {input item: count}, seconds a unit]
const RECIPES := {
	# Metals and materials (the markets buy them)
	"bronze_ingots": ["Bronze Ingots", "Materials", ["bronze_ingots", 1], {"copper_ore": 3, "tin_ore": 1}, 4.0],
	"girders": ["Girders", "Materials", ["girders", 1], {"iron_ore": 5}, 4.0],
	"hull_plates": ["Hull Plates", "Materials", ["hull_plates", 1], {"iron_ore": 4, "titanium_ore": 2}, 5.0],
	"rivets": ["Rivets", "Materials", ["rivets", 4], {"iron_ore": 2}, 2.0],
	"glass": ["Glass", "Materials", ["glass", 1], {"obsidian": 2, "salt": 1}, 3.0],
	"cables": ["Power Cables", "Materials", ["cables", 1], {"copper_ore": 3}, 3.0],
	"coolant": ["Coolant", "Materials", ["coolant", 1], {"ice": 4, "sulphur": 1}, 3.0],
	"fuel": ["Fuel", "Materials", ["fuel", 2], {"ice": 3}, 3.0],
	"water": ["Water", "Materials", ["water", 2], {"ice": 2}, 2.0],
	# Components (the markets buy them too)
	"bearings": ["Gears and Bearings", "Components", ["bearings", 1], {"iron_ore": 2, "cobalt": 1}, 4.0],
	"circuit_boards": ["Circuit Boards", "Components", ["circuit_boards", 1], {"copper_ore": 1, "silver_ore": 1, "obsidian": 1}, 5.0],
	"capacitors": ["Capacitor Banks", "Components", ["capacitors", 1], {"titanium_ore": 1, "silver_ore": 1, "cobalt": 1}, 5.0],
	"processors": ["Processors", "Components", ["processors", 1], {"circuit_boards": 2, "gold_ore": 1}, 7.0],
	"servos": ["Servos", "Components", ["servos", 1], {"bearings": 1, "cables": 1, "iron_ore": 1}, 6.0],
	"optic_fibre": ["Optic Fibre", "Components", ["optic_fibre", 2], {"glass": 1, "silver_ore": 1}, 4.0],
	"tools": ["Tools", "Components", ["tools", 1], {"iron_ore": 2, "bronze_ingots": 1}, 4.0],
	"reactor_coils": ["Reactor Coils", "Components", ["reactor_coils", 1], {"copper_ore": 4, "cobalt": 2, "titanium_ore": 1}, 7.0],
	# Spare parts (the Repair Bay)
	"spare_circuit": ["Spare Circuit Board", "Spare parts", ["spare_circuit", 1], {"circuit_boards": 1, "silver_ore": 1}, 6.0],
	"spare_conduit": ["Spare Conduit", "Spare parts", ["spare_conduit", 1], {"titanium_ore": 2, "copper_ore": 1}, 5.0],
	"spare_servo": ["Spare Servo", "Spare parts", ["spare_servo", 1], {"servos": 1}, 4.0],
	"spare_plate": ["Spare Plate", "Spare parts", ["spare_plate", 1], {"hull_plates": 1}, 4.0],
	"spare_lens": ["Spare Lens", "Spare parts", ["spare_lens", 1], {"glass": 1, "silver_ore": 1}, 5.0],
	"spare_cell": ["Spare Power Cell", "Spare parts", ["spare_cell", 1], {"capacitors": 1, "cobalt": 1}, 6.0],
	# Supplies
	"missile": ["Missiles", "Supplies", ["missile", 5], {"iron_ore": 2, "sulphur": 1, "circuit_boards": 1}, 6.0],
	"repair_kit": ["Repair Kit", "Supplies", ["repair_kit", 1], {"titanium_ore": 2, "iron_ore": 3, "circuit_boards": 1}, 6.0],
	# Weapons (extra small: for the small hardpoints)
	"wpn_laser": ["Pulse Cannon XS", "Weapons", ["wpn:laser:0", 1], {"iron_ore": 6, "copper_ore": 4, "circuit_boards": 2}, 10.0],
	"wpn_plasma": ["Plasma Cannon XS", "Weapons", ["wpn:plasma_cannon:0", 1], {"titanium_ore": 4, "cobalt": 2, "capacitors": 2}, 12.0],
	"wpn_missile": ["Missile Launcher XS", "Weapons", ["wpn:missile_launcher:0", 1], {"iron_ore": 6, "bearings": 2, "circuit_boards": 2}, 12.0],
	# Upgrade kits (fit an upgrade yourself: KITS)
	"upkit_1": ["Upgrade Kit Mk I", "Upgrade kits", ["upkit_1", 1], {"processors": 1, "hull_plates": 2, "titanium_ore": 4}, 12.0],
	"upkit_2": ["Upgrade Kit Mk II", "Upgrade kits", ["upkit_2", 1], {"processors": 2, "capacitors": 2, "platinum_ore": 3, "orichalcum": 1}, 18.0],
	"upkit_3": ["Upgrade Kit Mk III", "Upgrade kits", ["upkit_3", 1], {"processors": 3, "reactor_coils": 2, "gold_ore": 3, "orichalcum": 3, "quantum_cores": 1}, 25.0],
}
const CATEGORIES := ["Materials", "Components", "Spare parts", "Supplies", "Weapons", "Upgrade kits"]


static func recipe(id: String) -> Array:
	return RECIPES.get(id, [])


## How many units of recipe `id` the items can pay for.
static func can_make(items: Dictionary, id: String) -> int:
	var r := recipe(id)
	if r.is_empty():
		return 0
	var n := 999
	for k in r[3]:
		n = mini(n, int(items.get(k, 0)) / int(r[3][k]))
	return n


static func queue_of(data: Node) -> Array:
	if not data.industry.get("queue") is Array:
		data.industry["queue"] = []
	return data.industry["queue"]


## Orders `n` units refined (fragments `frag`) or made (recipe `id`): the inputs
## are taken now. False if there's no refinery / fabricator, or not enough.
static func order(data: Node, kind: String, id: String, n: int) -> bool:
	if n <= 0:
		return false
	if kind == "refine":
		if not data.has_equipment("refinery") or not Mining.is_frag(id) or data.count(id) < n:
			return false
		data.remove_item(id, n)
	else:
		if not data.has_equipment("fabricator") or can_make(data.items, id) < n:
			return false
		var r := recipe(id)
		for k in r[3]:
			data.remove_item(k, int(r[3][k]) * n)
	queue_of(data).append({"kind": kind, "id": id, "n": n, "done": 0, "t": 0.0})
	data.changed.emit()
	return true


## Takes an unfinished job off the queue: what wasn't made yet is given back.
static func cancel(data: Node, i: int) -> void:
	var q := queue_of(data)
	if i < 0 or i >= q.size():
		return
	var j: Dictionary = q[i]
	var left := int(j["n"]) - int(j["done"])
	if j["kind"] == "refine":
		data.add_item(j["id"], left)
	else:
		var r := recipe(j["id"])
		for k in r[3]:
			data.add_item(k, int(r[3][k]) * left)
	q.remove_at(i)
	data.changed.emit()


## A unit's time: a recipe's, or refining (faster with the reactor's refinery upgrade).
static func unit_time(data: Node, job: Dictionary) -> float:
	if job["kind"] == "refine":
		return REFINE_TIME / (1.0 + data.mod("refine_speed"))
	return float(recipe(job["id"])[4])


## What a unit of the job puts out: [[item, count]...].
static func output(job: Dictionary, rng: RandomNumberGenerator) -> Array:
	if job["kind"] == "refine":
		var m := Mining.mineral_of(job["id"])
		if m == "rubble":
			var out := [["scrap", 1]]
			if rng.randf() < 0.25:
				out.append([["iron_ore", "copper_ore", "tin_ore", "sulphur", "salt"][rng.randi() % 5], 1])
			return out
		return [[m, 1]]
	var r := recipe(job["id"])
	return [[r[2][0], int(r[2][1])]]


## The industry goes on: the first job a unit at a time (the others wait their
## turn). Returns the things made this time ([[item, count]...]).
static func tick(data: Node, delta: float, rng: RandomNumberGenerator) -> Array:
	var made := []
	var q := queue_of(data)
	if q.is_empty():
		return made
	var j: Dictionary = q[0]
	var need: bool = (j["kind"] == "refine" and data.has_equipment("refinery")) or (j["kind"] == "fab" and data.has_equipment("fabricator"))
	if not need:
		return made
	j["t"] = float(j["t"]) + delta
	var ut := unit_time(data, j)
	while float(j["t"]) >= ut and int(j["done"]) < int(j["n"]):
		var out := output(j, rng)
		var cap := Shipyard.cargo_capacity(data)
		if not out.all(func(o): return Hardpoints.is_weapon(o[0]) or Inventory.room_for(data.items, o[0], cap) >= int(o[1]) or not Items.is_cargo(o[0])):
			j["t"] = ut   # (the hold's full: it waits)
			j["waiting"] = true
			return made
		j.erase("waiting")
		j["t"] = float(j["t"]) - ut
		j["done"] = int(j["done"]) + 1
		for o in out:
			data.add_item(o[0], int(o[1]))
			made.append(o)
	if int(j["done"]) >= int(j["n"]):
		q.remove_at(0)
	if not made.is_empty():
		data.changed.emit()
	return made


## A kit can raise `id` (body `which`) from its level now?
static func kit_fits(kit: String, ups: Dictionary, which: String, id: String) -> bool:
	var l := Upgrades.level(ups, which, id)
	var band: Array = KITS.get(kit, [9, 9])
	return l >= int(band[0]) and l <= int(band[1]) and l < Upgrades.MAX_LEVEL


## Fits a kit: the stat a level up, the kit used. False if it doesn't fit.
static func fit_kit(data: Node, kit: String, which: String, id: String) -> bool:
	if data.count(kit) <= 0 or not kit_fits(kit, data.upgrades, which, id):
		return false
	data.remove_item(kit, 1)
	Upgrades.raise(data.upgrades, which, id)
	data.changed.emit()
	return true
