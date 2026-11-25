class_name LostItems
## What you lose when you die, and win back. Dying - your ship destroyed in
## space (Main.respawn_state) or knocked out on a planet (PlanetSurface.
## knocked_out) - loses one thing you carry: a random stack from your
## inventory (an item and all of its count) or a piece of your toolbar's
## equipment (a weapon or a ship system - never the basic laser, never a story
## item). It goes on your lost list (player "lost": [{kind, id, n}], saved).
## Every NPC you kill yourself - a ship in space, a pirate or an animal on a
## planet - has a REGAIN_CHANCE chance to bring one lost thing back (a random
## one); RegainPopup shows "ITEM REGAINED" with its name.
## Works on the save format of the player (a Dictionary: items {id: n},
## equipment [ids], lost [...]) - PlayerData has its own copy of regain.

const REGAIN_CHANCE := 0.1
## Equipment never lost (what every ship has).
const KEPT := ["laser"]


## Loses one thing from `player` (the save format) onto its lost list; its
## name ("" if there was nothing to lose). `from`: "items" - the ship's hold
## and its equipment (your ship destroyed); "carried" - what you carry on foot
## (knocked out on a planet).
static func lose_one(player: Dictionary, roll := -1.0, from := "items") -> String:
	var choices := []
	var items: Dictionary = Inventory.carried(player) if from == "carried" else player.get("items", {})
	for id in items:
		if int(items[id]) > 0 and Items.info(id).get("kind", "") != "quest":
			choices.append({"kind": "item", "id": id, "n": int(items[id])})
	if from == "items":
		for id in player.get("equipment", []):
			if not id in KEPT:
				choices.append({"kind": "equipment", "id": id, "n": 1})
		# A fitted weapon (Hardpoints) - never a small Pulse Cannon: won back into the hold.
		var ws: Array = player.get("weapons", [])
		for i in ws.size():
			var w := str(ws[i])
			if w != "" and not (Hardpoints.kind(w) in KEPT and Hardpoints.size_of(w) <= Hardpoints.BASE):
				choices.append({"kind": "item", "id": w, "n": 1, "slot": i})
	if choices.is_empty():
		return ""
	choices.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))   # (the same roll, the same pick)
	var r := roll if roll >= 0.0 else randf()
	var e: Dictionary = choices[mini(int(r * choices.size()), choices.size() - 1)]
	if e.has("slot"):
		player["weapons"][int(e["slot"])] = ""
		e.erase("slot")
	elif e["kind"] == "item":
		items.erase(e["id"])
	else:
		var eq: Array = player["equipment"]
		eq.erase(e["id"])
	if not player.has("lost"):
		player["lost"] = []
	(player["lost"] as Array).append(e)
	return label(e)


## A kill's chance (roll < REGAIN_CHANCE) to win one lost thing back into
## `player`; its name ("" if not this time).
static func regain(player: Dictionary, roll := -1.0) -> String:
	var lost: Array = player.get("lost", [])
	var r := roll if roll >= 0.0 else randf()
	if lost.is_empty() or r >= REGAIN_CHANCE:
		return ""
	var e: Dictionary = lost.pop_at(int(r / REGAIN_CHANCE * lost.size()) % lost.size())
	if e["kind"] == "item":
		var items: Dictionary = player.get("items", {})
		items[e["id"]] = int(items.get(e["id"], 0)) + int(e["n"])
		player["items"] = items
	else:
		var eq: Array = player.get("equipment", [])
		if not e["id"] in eq:
			eq.append(e["id"])
		player["equipment"] = eq
	return label(e)


## "Repair Kit x2", "Plasma Cannon".
static func label(e: Dictionary) -> String:
	var name := Items.display_name(e["id"]) if e["kind"] == "item" else str(Items.EQUIPMENT.get(e["id"], {}).get("name", e["id"]))
	return name + (" x%d" % int(e["n"]) if int(e["n"]) > 1 else "")
