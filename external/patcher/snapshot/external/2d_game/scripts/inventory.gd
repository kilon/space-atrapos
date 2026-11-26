class_name Inventory
## Slot inventories: every item stacks up to STACK in a slot (250 iron ore
## take 3 slots). Your ship's hold has its class's slots (Shipyard.CLASS_HOLD;
## Cargo Racks add more), up to SHIP_SLOTS (Shipyard.cargo_capacity); on a planet you carry PLAYER_SLOTS slots of your
## own (player "carried": {id: n}, saved) - what you pick up there goes to you,
## and you move it to and from your ship at the ship (TransferPanel). Both
## toolbars (in space and on foot) have TOOLBAR_SLOTS slots you fill yourself:
## hover something usable in the inventory and press 1-9 (right-click a slot
## to empty it).
## An inventory here is a Dictionary {id: count}; credits are never in one.

const STACK := 100
const SHIP_SLOTS := 120          # the most any ship can have (Shipyard.CLASS_HOLD sets each class's)
const PLAYER_SLOTS := 12
const TOOLBAR_SLOTS := 9
## The toolbars as a new pilot has them: the ship's weapons and systems, your
## rifle and supplies on foot ("" = an empty slot).
const SHIP_TOOLBAR := ["laser", "plasma_cannon", "missile_launcher", "afterburner", "shield_booster", "repair_kit", "", "", ""]
const FOOT_TOOLBAR := ["rifle", "medicine", "energy_cell", "", "", "", "", "", ""]
## What can go on the toolbar on foot.
const FOOT_USABLE := ["rifle", "medicine", "energy_cell"]


## Usable on foot (toolbar, a click in the field inventory): FOOT_USABLE,
## food and energy drinks (Stamina), and skills ("skill:<id>": Skills).
static func foot_usable(id: String) -> bool:
	return id in FOOT_USABLE or Stamina.restores(id) > 0.0 or Skills.valid(id)


## Slots an item count takes.
static func slots_for(n: int) -> int:
	return ceili(n / float(STACK)) if n > 0 else 0


static func slots_used(inv: Dictionary) -> int:
	var s := 0
	for id in inv:
		s += slots_for(int(inv[id]))
	return s


## How many more of `id` fit: the empty slots' worth, and the rest of its last stack.
static func room_for(inv: Dictionary, id: String, cap: int) -> int:
	var n := int(inv.get(id, 0))
	var partial := (STACK - n % STACK) % STACK if n > 0 else 0
	return maxi(0, cap - slots_used(inv)) * STACK + partial


## Puts up to `amount` of `id` in; how many went in.
static func add(inv: Dictionary, id: String, amount: int, cap: int) -> int:
	var n := mini(amount, room_for(inv, id, cap))
	if n > 0:
		inv[id] = int(inv.get(id, 0)) + n
	return n


static func take(inv: Dictionary, id: String, amount: int) -> int:
	var n := mini(amount, int(inv.get(id, 0)))
	if n > 0:
		inv[id] = int(inv[id]) - n
		if int(inv[id]) <= 0:
			inv.erase(id)
	return n


## Moves one stack's worth (up to STACK) of `id` from one inventory to another
## (as much as it has room for); how many moved.
static func move_stack(from: Dictionary, to: Dictionary, id: String, to_cap: int) -> int:
	var n := int(from.get(id, 0))
	if n <= 0:
		return 0
	var stack := n % STACK if n % STACK != 0 else STACK   # (the last, partial stack first)
	var moved := add(to, id, mini(stack, n), to_cap)
	take(from, id, moved)
	return moved


## The slots to draw: [[id, count], ...] - full stacks then the remainder,
## items in name order.
static func stacks(inv: Dictionary) -> Array:
	var out := []
	var ids := inv.keys().filter(func(id): return int(inv[id]) > 0 and Items.exists(id))
	ids.sort()
	for id in ids:
		var n := int(inv[id])
		while n > 0:
			out.append([id, mini(n, STACK)])
			n -= STACK
	return out


## The slots as laid out: an inventory's slot layout (an Array of ids, one per
## slot; "" empty) puts each item where you dragged it. Returns `cap` slots,
## each [id, count] or [] (empty): an item's stacks fill the slots the layout
## gives it first, in order (full stacks first); what's left goes to the first
## empty slots (and the layout learns it); slots of items you no longer have
## are emptied. The layout is resized to `cap` and updated in place.
static func slots(inv: Dictionary, layout: Array, cap: int) -> Array:
	layout.resize(cap)
	for i in cap:
		if layout[i] == null:
			layout[i] = ""
	var left := {}
	for id in inv:
		if int(inv[id]) > 0 and Items.exists(id):
			left[id] = int(inv[id])
	var out := []
	out.resize(cap)
	for i in cap:
		var id: String = layout[i]
		if id != "" and int(left.get(id, 0)) > 0:
			var n := mini(STACK, int(left[id]))
			out[i] = [id, n]
			left[id] = int(left[id]) - n
		else:
			out[i] = []
			layout[i] = ""
	var ids := left.keys().filter(func(id): return int(left[id]) > 0)
	ids.sort()
	var free := 0
	for id in ids:
		while int(left[id]) > 0:
			while free < cap and not (out[free] as Array).is_empty():
				free += 1
			if free >= cap:
				return out   # (more than fits: shown as far as it goes)
			var n := mini(STACK, int(left[id]))
			out[free] = [id, n]
			layout[free] = id
			left[id] = int(left[id]) - n
	return out


## Dragging slot `a` onto slot `b` of the same inventory: they swap places
## (or the stack moves, if `b` is empty).
static func swap(layout: Array, a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= layout.size() or b >= layout.size():
		return
	var t = layout[a]
	layout[a] = layout[b]
	layout[b] = t


## A drop from one inventory onto slot `slot` of another: one stack of `id`
## moves across (as far as there's room), into that slot if it's free.
static func move_stack_into(from: Dictionary, to: Dictionary, id: String, to_cap: int, to_layout: Array, slot: int) -> int:
	if slot >= 0 and slot < to_layout.size() and str(to_layout[slot]) == "":
		to_layout[slot] = id
	return move_stack(from, to, id, to_cap)


## A player's layout for an inventory ("hold" or "carried": player
## "layout_hold" / "layout_carried").
static func layout(player: Dictionary, which: String) -> Array:
	var key := "layout_" + which
	if not player.get(key) is Array:
		player[key] = []
	return player[key]


## What you carry on a planet (player "carried"; an older save's "pack" moves in).
static func carried(player: Dictionary) -> Dictionary:
	if not player.has("carried") or not player["carried"] is Dictionary:
		player["carried"] = {}
	var old: Dictionary = player.get("pack", {})
	if not old.is_empty():
		for id in old:
			player["carried"][id] = int(player["carried"].get(id, 0)) + int(old[id])
		player.erase("pack")
	return player["carried"]


## A toolbar (player "toolbar" in space, "toolbar_foot" on foot): always
## TOOLBAR_SLOTS entries (an id or "").
static func toolbar(player: Dictionary, foot: bool) -> Array:
	var key := "toolbar_foot" if foot else "toolbar"
	var t: Array = player.get(key, [])
	if t.size() != TOOLBAR_SLOTS:
		var base: Array = (FOOT_TOOLBAR if foot else SHIP_TOOLBAR).duplicate()
		for i in mini(t.size(), TOOLBAR_SLOTS):
			base[i] = str(t[i])
		t = base
		player[key] = t
	return t


## A drop onto toolbar slot `i` (drag and drop): another of its slots - they
## swap; something usable from an inventory - it goes there (and leaves the
## slot it was in, if any). True if it was taken. Payloads: {src: "toolbar",
## which: "ship" / "foot", index, id} or {src: "hold" / "carried" / "gear", id}.
static func toolbar_drop(bar: Array, i: int, data: Dictionary, foot: bool) -> bool:
	if i < 0 or i >= bar.size():
		return false
	if data.get("src") == "toolbar":
		if data.get("which") != ("foot" if foot else "ship"):
			return false
		var j: int = data.get("index", -1)
		if j < 0 or j >= bar.size():
			return false
		var t = bar[i]
		bar[i] = bar[j]
		bar[j] = t
		return true
	var id: String = toolbar_id(str(data.get("id", "")), foot)
	if id == "":
		return false
	var was := bar.find(id)
	if was >= 0:
		bar[was] = bar[i] if was != i else ""   # (one slot per tool: what was here goes where it came from)
	bar[i] = id
	return true


## What a dragged thing is on a toolbar ("" - it can't go there).
static func toolbar_id(id: String, foot: bool) -> String:
	if foot:
		if id == "laser" or id == "rifle":
			return "rifle"
		return id if foot_usable(id) else ""
	return id if ship_usable(id) else ""


static func toolbar_accepts(data: Dictionary, foot: bool) -> bool:
	if data.get("src") == "toolbar":
		return data.get("which") == ("foot" if foot else "ship")
	return toolbar_id(str(data.get("id", "")), foot) != ""


## Can `id` go on the ship's toolbar? (a weapon, a ship system)
static func ship_usable(id: String) -> bool:
	return Items.WEAPONS.has(id) or Items.SYSTEMS.has(id)
