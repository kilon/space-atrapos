class_name Hardpoints
extends RefCounted
## Ship weapons in sizes, and the hardpoints they're fitted to. A ship class
## has a row of hardpoints, each of a size from XS to XXL (LAYOUT: two on an
## interceptor, 24 on a dreadnought); a weapon is an item of a kind
## (Items.WEAPONS) and a size - "wpn:<kind>:<size>", e.g. "wpn:plasma_cannon:3"
## (a Plasma Cannon L) - that fits any hardpoint its size or bigger. Every
## weapon fitted fires at your target on its own (Ship._update_weapons), each
## from its own place on the hull; the toolbar switches a kind on and off.
## Items.WEAPONS' numbers are size S; each size up hits DAMAGE_STEP harder,
## fires INTERVAL_STEP slower, reaches RANGE_STEP further and costs PRICE_STEP
## more. Fitted weapons: PlayerData.weapons (an item id or "" a hardpoint).
## Other ships carry a loadout for their class too (loadout(): Enemy).

const PREFIX := "wpn:"
const SIZES := ["XS", "S", "M", "L", "XL", "XXL"]
const SIZE_NAMES := ["Extra small", "Small", "Medium", "Large", "Extra large", "Huge"]
## The size Items.WEAPONS' numbers are for (S).
const BASE := 1
const DAMAGE_STEP := 1.7
const INTERVAL_STEP := 1.1
const RANGE_STEP := 1.07
const SPEED_STEP := 0.96
const PRICE_STEP := 2.6
## The sizes each kind is made in [smallest, biggest].
const MADE_IN := {"laser": [0, 4], "plasma_cannon": [0, 5], "missile_launcher": [0, 5],
	"beam": [1, 5], "bouncer": [1, 4], "electro": [1, 4]}
## The kinds, in the order the outfitter lists them.
const KINDS := ["laser", "plasma_cannon", "missile_launcher", "beam", "bouncer", "electro"]

## What your first ship starts with: a Pulse Cannon S.
const START := ["wpn:laser:1", "", ""]

## Each class's hardpoints, biggest first ("player": the Atrapos you start in).
const LAYOUT := {
	"player": [1, 0, 0],
	"interceptor": [0, 0],
	"fighter": [1, 1, 0],
	"courier": [1, 0],
	"explorer": [1, 1],
	"freighter": [1, 0],
	"gunship": [2, 2, 1, 1],
	"frigate": [3, 3, 2, 2, 2, 2, 1, 1, 1, 1],
	"cruiser": [4, 4, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 1, 1],
	"battleship": [5, 4, 4, 4, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 1, 1],
	"dreadnought": [5, 5, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1],
}


static func item_id(kind: String, size: int) -> String:
	return "%s%s:%d" % [PREFIX, kind, clampi(size, 0, SIZES.size() - 1)]


static func is_weapon(id: String) -> bool:
	return id.begins_with(PREFIX)


## [kind, size] of a weapon item id, or [] if it isn't one.
static func parse(id: String) -> Array:
	if not is_weapon(id):
		return []
	var p := id.substr(PREFIX.length()).split(":")
	if p.size() != 2 or not Items.WEAPONS.has(p[0]):
		return []
	return [p[0], clampi(int(p[1]), 0, SIZES.size() - 1)]


static func kind(id: String) -> String:
	var p := parse(id)
	return p[0] if not p.is_empty() else ""


static func size_of(id: String) -> int:
	var p := parse(id)
	return p[1] if not p.is_empty() else 0


static func sizes(kind: String) -> Array:
	var r: Array = MADE_IN.get(kind, [BASE, BASE])
	return range(r[0], r[1] + 1)


static func title(id: String) -> String:
	var p := parse(id)
	return "%s %s" % [Items.EQUIPMENT[p[0]]["name"], SIZES[p[1]]] if not p.is_empty() else id


static func price(id: String) -> int:
	var p := parse(id)
	if p.is_empty():
		return 0
	# (the Pulse Cannon is free for your first ship: priced as a plasma cannon's two-thirds)
	var base := float(Items.EQUIPMENT[p[0]]["price"]) if p[0] != "laser" else 400.0
	return snappedi(roundi(base * pow(PRICE_STEP, p[1] - BASE)), 10)


## Its numbers at its size: Items.WEAPONS' entry for the kind with damage,
## interval, range and speed scaled, and "size".
static func stats(id: String) -> Dictionary:
	var p := parse(id)
	if p.is_empty():
		return Items.WEAPONS["laser"]
	var w: Dictionary = Items.WEAPONS[p[0]].duplicate()
	var k: int = p[1] - BASE
	w["damage"] = float(w["damage"]) * pow(DAMAGE_STEP, k)
	w["interval"] = float(w["interval"]) * pow(INTERVAL_STEP, k)
	w["range"] = float(w["range"]) * pow(RANGE_STEP, k)
	w["speed"] = float(w["speed"]) * pow(SPEED_STEP, k)
	w["size"] = p[1]
	return w


## Items-style info (Items.info): name, kind "weapon", value, price, desc.
static func info(id: String) -> Dictionary:
	var p := parse(id)
	if p.is_empty():
		return {}
	var w := stats(id)
	return {"name": title(id), "kind": "weapon", "value": roundi(price(id) * Gear.SELL_SHARE), "price": price(id),
		"desc": "A ship weapon, size %s (fits a hardpoint of %s or bigger). %s %s" % [SIZES[p[1]], SIZES[p[1]],
			Items.EQUIPMENT[p[0]]["desc"], describe(id)]}


## Its numbers in words.
static func describe(id: String) -> String:
	var w := stats(id)
	if w["style"] == "beam":
		return "%.0f damage a second, reach %.0f." % [w["damage"], w["range"]]
	return "%.0f damage every %.2f s, reach %.0f." % [w["damage"], w["interval"], w["range"]]


## The weapon kind's icon with its size on it.
static func draw_icon(ci: CanvasItem, id: String, rect: Rect2, dim := false) -> void:
	var p := parse(id)
	if p.is_empty():
		return
	Items.draw_icon(ci, p[0], rect, dim)
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var col := Color(1.0, 0.85, 0.4) if not dim else Color(0.55, 0.5, 0.35)
	ci.draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - r * 0.95, rect.size.y - r * 0.12), SIZES[p[1]],
		HORIZONTAL_ALIGNMENT_RIGHT, r * 0.9, maxi(9, int(r * 0.46)), col)


# --- A class's hardpoints ------------------------------------------------------------

## The hardpoints' sizes of a ship class (a design id or "player").
static func layout(ship_class: String) -> Array:
	if ship_class == "" or ship_class == "player":
		return LAYOUT["player"]
	return LAYOUT.get(str(EnemyTypes.get_type(ship_class).get("class", "fighter")), LAYOUT["fighter"])


## The hardpoints in words: "2×L 4×M 4×S".
static func summary(lay: Array) -> String:
	var counts := {}
	for z in lay:
		counts[int(z)] = int(counts.get(int(z), 0)) + 1
	var keys := counts.keys()
	keys.sort()
	keys.reverse()
	return " ".join(keys.map(func(z): return "%d×%s" % [counts[z], SIZES[z]]))


static func fits(id: String, slot_size: int) -> bool:
	return not parse(id).is_empty() and size_of(id) <= slot_size


## Where hardpoint `i` of `n` sits on a hull `half` (half its length, half its
## width; the nose up, -y): in pairs side by side, from the nose back, the
## biggest guns along the spine.
static func mount(i: int, n: int, half: Vector2) -> Vector2:
	if n <= 1:
		return Vector2(0, -half.y * 0.45)
	var rows := ceili(n / 2.0)
	var row := i / 2
	var side := -1.0 if i % 2 == 0 else 1.0
	if n % 2 == 1 and i == n - 1:
		side = 0.0
	var y := lerpf(-0.5, 0.45, float(row) / maxf(1.0, rows - 1.0)) * half.y
	var x := side * half.x * lerpf(0.18, 0.55, float(row) / maxf(1.0, rows - 1.0))
	return Vector2(x, y)


# --- The player's hardpoints (PlayerData.weapons) ---------------------------------------

## The fitted weapons, one entry a hardpoint ("" empty), sized to the class.
static func fitted(data: Node) -> Array:
	var lay := layout(data.ship_class)
	if data.weapons.size() != lay.size():
		data.weapons.resize(lay.size())
		for i in data.weapons.size():
			if data.weapons[i] == null:
				data.weapons[i] = ""
	return data.weapons


## The emptiest hardpoint `id` fits (the smallest that takes it), or -1.
static func free_slot_for(data: Node, id: String) -> int:
	var lay := layout(data.ship_class)
	var ws := fitted(data)
	var best := -1
	for i in lay.size():
		if ws[i] == "" and fits(id, lay[i]) and (best < 0 or lay[i] < lay[best]):
			best = i
	return best


## Fits weapon `id` from the hold (or bought: `from_hold` false) to hardpoint
## `slot` (-1: the best free one). False if it doesn't fit.
static func fit(data: Node, id: String, slot := -1, from_hold := true) -> bool:
	var lay := layout(data.ship_class)
	var ws := fitted(data)
	if slot < 0:
		slot = free_slot_for(data, id)
	if slot < 0 or slot >= lay.size() or not fits(id, lay[slot]):
		return false
	if from_hold:
		if data.count(id) <= 0:
			return false
		data.remove_item(id)
	if ws[slot] != "":
		Inventory.add(data.items, ws[slot], 1, Shipyard.cargo_capacity(data))   # (the one there: to the hold)
	ws[slot] = id
	data.discovered["gear:" + kind(id)] = true
	_toolbar_has(data, kind(id))
	data.changed.emit()
	return true


## Takes hardpoint `slot`'s weapon out into the hold (false: no room).
static func unfit(data: Node, slot: int) -> bool:
	var ws := fitted(data)
	if slot < 0 or slot >= ws.size() or ws[slot] == "":
		return false
	if Inventory.room_for(data.items, ws[slot], Shipyard.cargo_capacity(data)) < 1:
		return false
	Inventory.add(data.items, ws[slot], 1, Shipyard.cargo_capacity(data))
	ws[slot] = ""
	data.changed.emit()
	return true


## Is a weapon of `kind` fitted?
static func has_kind(data: Node, k: String) -> bool:
	for id in fitted(data):
		if id != "" and kind(id) == k:
			return true
	return false


## A kind on the toolbar (its key switches the kind on and off): put there the
## first time one is fitted.
static func _toolbar_has(data: Node, k: String) -> void:
	if not k in data.toolbar:
		var free: int = data.toolbar.find("")
		if free >= 0:
			data.toolbar[free] = k


## A ship changed (bought): its weapons that still fit stay on (biggest into
## the biggest hardpoints), the rest go to the hold - or are sold, no room.
## Returns the drachmas the unplaced ones fetched.
static func refit(data: Node, old: Array) -> int:
	var lay := layout(data.ship_class)
	data.weapons = []
	for i in lay.size():
		data.weapons.append("")
	var list := old.filter(func(x): return str(x) != "")
	list.sort_custom(func(a, b): return size_of(a) > size_of(b))
	var sold := 0
	for id in list:
		var s := free_slot_for(data, id)
		if s >= 0:
			data.weapons[s] = id
		elif Inventory.room_for(data.items, id, Shipyard.cargo_capacity(data)) >= 1:
			Inventory.add(data.items, id, 1, Shipyard.cargo_capacity(data))
		else:
			sold += roundi(price(id) * Gear.SELL_SHARE)
	return sold


## An older save's weapons ("equipment": the kinds owned, one of each): each
## fitted at the biggest size its hardpoint takes, the starting Pulse Cannon S
## first.
static func from_equipment(data: Node, kinds: Array) -> void:
	var lay := layout(data.ship_class)
	data.weapons = []
	for i in lay.size():
		data.weapons.append("")
	var order := KINDS.filter(func(k): return k in kinds or k == "laser")
	for k in order:
		var best := -1
		for i in lay.size():
			if data.weapons[i] == "" and int(lay[i]) >= int(MADE_IN[k][0]) and (best < 0 or lay[i] > lay[best]):
				best = i
		if best >= 0:
			data.weapons[best] = item_id(k, mini(int(lay[best]), int(MADE_IN[k][1])) if k != "laser" else mini(int(lay[best]), BASE))
		else:
			Inventory.add(data.items, item_id(k, maxi(BASE, int(MADE_IN[k][0]))), 1, Shipyard.cargo_capacity(data))


# --- Other ships' loadouts ----------------------------------------------------------------

## The weapon kinds an NPC ship carries, by its job (warships the heavy ones).
const NPC_KINDS := {"patrol": ["laser", "plasma_cannon", "missile_launcher"], "pirate": ["laser", "plasma_cannon"],
	"trader": ["laser"], "miner": ["laser"], "explorer": ["laser"], "": ["laser", "plasma_cannon", "missile_launcher"]}

## A loadout for a ship of `ship_class` doing `role`: [weapon item id] - one
## a hardpoint (a civilian fills half of them), the same draw for the same seed.
static func loadout(ship_class: String, role: String, seed_n: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	var lay := layout(ship_class)
	var kinds: Array = NPC_KINDS.get(role, NPC_KINDS[""])
	var civil := role in ["trader", "miner", "explorer"]
	var out := []
	for i in lay.size():
		if civil and i % 2 == 1:
			continue
		var k: String = kinds[rng.randi() % kinds.size()]
		var r: Array = MADE_IN[k]
		if int(lay[i]) < int(r[0]):
			k = "laser"
		out.append(item_id(k, clampi(int(lay[i]), int(MADE_IN[k][0]), int(MADE_IN[k][1]))))
	return out
