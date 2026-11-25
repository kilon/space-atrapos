class_name Inventory
## Slot inventories: every item stacks up to STACK in a slot (250 iron ore
## take 3 slots). Your ship's hold has its class's slots (Shipyard.CLASS_HOLD;
## Cargo Racks add more), up to SHIP_SLOTS (Shipyard.cargo_capacity); on a planet you carry PLAYER_SLOTS slots of your
## own (player "carried": {id: n}, saved) - what you pick up there goes to you,
## and you move it to and from your ship at the ship (TransferPanel). Both
## toolbars (in space and on foot) have TOOLBAR_SLOTS slots you fill yourself:
## drag anything usable onto a slot (toolbar_drop - what a slot can hold:
## toolbar_kind), drag a slot off the bar to empty it.
## An inventory here is a Dictionary {id: count}; credits are never in one.

const STACK := 100
const SHIP_SLOTS := 120          # the most any ship can have (Shipyard.CLASS_HOLD sets each class's)
const PLAYER_SLOTS := 12
const TOOLBAR_SLOTS := 9
## The toolbars as a new pilot has them: the ship's weapons and systems; on
## foot an empty bar - you put there what you want ("" = an empty slot).
const SHIP_TOOLBAR := ["laser", "plasma_cannon", "missile_launcher", "afterburner", "shield_booster", "", "", "", ""]
const FOOT_TOOLBAR := ["tool:rifle", "tool:beam", "tool:digger", "tool:scanner", "tool:build", "", "", "", ""]   # (a new game: the automaton's five tools on 1-5)
## The automaton's tools, always with it (not items in an inventory): the
## rifle out (the loadout's weapon), the mining beam (the rifle's, on a
## deposit), the terrain digger, the ground scanner, the builder. An older save's "rifle"
## is TOOL_RIFLE.
const TOOL_RIFLE := "tool:rifle"
const TOOLS := {
	"tool:rifle": {"name": "Rifle", "desc": "The automaton's weapon out (its loadout's): fire at what's in the sights."},
	"tool:beam": {"name": "Mining Beam", "desc": "The rifle's mining beam: fire with a mineral deposit in the sights and it cuts the vein."},
	"tool:digger": {"name": "Terrain Digger", "desc": "Out in place of the rifle: fire and the beam carves the ground away. Again: the rifle back."},
	"tool:scanner": {"name": "Ground Scanner", "desc": "In hand, the left button sends a pulse over the ground round you: ore, ruins and what lives here marked for a while (Z: a pulse whatever's in hand)."},
	"tool:build": {"name": "Builder", "desc": "In hand: a preview of a building piece where you aim, snapped to what's built - a click places it (its stone, timber, marble or bronze from what you carry and your hold); held and dragged, a run of them. N the pieces, K turns it, O demolish / upgrade / paint, P snapping."},
}
## Usable on foot from a toolbar slot besides gear, tools and food (Stamina):
## medicine heals the automaton.
const FOOT_USABLE := ["medicine"]


static func is_tool_id(id: String) -> bool:
	return TOOLS.has(id)


## What a toolbar slot's id is: "tool" (the automaton's), "gear" (automaton
## gear: equipped or not), "ship_gear" (a ship module, fitted or in the hold),
## "weapon" (a ship weapon kind: its key switches it on and off), "weapon_item"
## (a ship weapon in the hold: pressed, fitted), "system" (a ship system),
## "consumable" (food, drinks, medicine, fuel...), "skill" -
## or "" (nothing a toolbar can hold, there).
static func toolbar_kind(id: String, foot: bool) -> String:
	if id == "":
		return ""
	if foot:
		if is_tool_id(id):
			return "tool"
		if Gear.side(id) == "foot":
			return "gear"
		if Skills.valid(id):
			return "skill"
		if id in FOOT_USABLE or Stamina.restores(id) > 0.0:
			return "consumable"
		return ""
	if Items.WEAPONS.has(id):
		return "weapon"
	if Items.SYSTEMS.has(id):
		return "system"
	if Hardpoints.is_weapon(id) and not Hardpoints.parse(id).is_empty():
		return "weapon_item"
	if Gear.side(id) == "ship":
		return "ship_gear"
	if id == "fuel":
		return "consumable"
	return ""


## Usable on foot (a toolbar slot, a click in the field inventory).
static func foot_usable(id: String) -> bool:
	return toolbar_kind(id, true) != ""


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
## TOOLBAR_SLOTS entries (an id or ""; an older save's "rifle" is TOOL_RIFLE).
static func toolbar(player: Dictionary, foot: bool) -> Array:
	var key := "toolbar_foot" if foot else "toolbar"
	var t: Array = player.get(key, [])
	if t.size() != TOOLBAR_SLOTS or (foot and t.has("rifle")):
		var base: Array = (FOOT_TOOLBAR if foot else SHIP_TOOLBAR).duplicate()
		for i in mini(t.size(), TOOLBAR_SLOTS):
			base[i] = str(t[i]) if t[i] != null else ""
			if foot and base[i] == "rifle":
				base[i] = TOOL_RIFLE
		t = base
		player[key] = t
	return t


## A drop onto toolbar slot `i` (drag and drop): another of its slots - they
## swap; anything it can hold (toolbar_kind), from an inventory, the automaton's
## loadout or tools, the ship's fittings or the other toolbar - it goes there
## (and leaves the slot it was in, if any: one slot a thing). True if it was
## taken. Payloads: {src: "toolbar", which: "ship" / "foot", index, id} or
## {src: "hold" / "carried" / "gear" / "loadout" / "tool", id}.
static func toolbar_drop(bar: Array, i: int, data: Dictionary, foot: bool) -> bool:
	if i < 0 or i >= bar.size():
		return false
	if data.get("src") == "toolbar" and data.get("which") == ("foot" if foot else "ship"):
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
		bar[was] = bar[i] if was != i else ""   # (one slot per thing: what was here goes where it came from)
	bar[i] = id
	return true


## A toolbar slot dragged off the bar (dropped anywhere else): emptied.
static func toolbar_clear(bar: Array, i: int) -> void:
	if i >= 0 and i < bar.size():
		bar[i] = ""


## What a dragged thing is on a toolbar ("" - it can't go there).
static func toolbar_id(id: String, foot: bool) -> String:
	if foot and id == "rifle":
		return TOOL_RIFLE
	if foot and id in Items.WEAPONS:
		return ""   # (a ship's weapon kind: not on foot)
	return id if toolbar_kind(id, foot) != "" else ""


static func toolbar_accepts(data: Dictionary, foot: bool) -> bool:
	if data.get("src") == "toolbar" and data.get("which") == ("foot" if foot else "ship"):
		return true
	return toolbar_id(str(data.get("id", "")), foot) != ""


## Can `id` go on the ship's toolbar?
static func ship_usable(id: String) -> bool:
	return toolbar_kind(id, false) != ""


## How many of a toolbar slot's item you have to use (-1: not counted - a
## tool, a ship system, a weapon kind, gear on the automaton): on foot what
## you carry and the hold together, in space the hold.
static func toolbar_count(data: Node, id: String, foot: bool) -> int:
	match toolbar_kind(id, foot):
		"consumable", "weapon_item", "ship_gear":
			return int(data.items.get(id, 0)) + (int(data.carried.get(id, 0)) if foot else 0)
		"gear":
			return -1 if toolbar_equipped(data, id, foot) else int(data.items.get(id, 0)) + int(data.carried.get(id, 0))
		"weapon":
			return int(data.items.get("missile", 0)) if id == "missile_launcher" else -1
	return -1


## Whether a toolbar slot's thing is on: gear in the automaton's loadout, a
## ship module fitted.
static func toolbar_equipped(data: Node, id: String, foot: bool) -> bool:
	match toolbar_kind(id, foot):
		"gear":
			return data.loadout.values().has(id)
		"ship_gear":
			var p := Gear.parse(id)
			for m in data.modules:
				if str(m.get("id", "")) == p[0] and int(m.get("rating", -1)) == int(p[1]):
					return true
	return false
