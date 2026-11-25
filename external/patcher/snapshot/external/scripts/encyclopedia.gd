class_name Encyclopedia
extends RefCounted
## The encyclopedia (a book of the Archive): your ship, enemy and neutral ship
## classes, stations, asteroids, weapons, systems, items, celestial bodies and
## the lore of ancient Greece. Only what you've discovered is listed
## (Discovery: a ship class that came near, a station you came up to, an
## asteroid kind you got close to, a planet or nebula you flew by, gear seen
## at an outfitter or fitted, an item you've held) - an empty category says
## how to find its entries. The lore unlocks with the main quest (locked
## entries show as ? ? ?). Each entry: {id, title, kind, text, ...} - kind says
## how its picture is drawn (Preview).

const HINTS := {"ship": "None met yet: fly near ships to learn about their classes.",
	"station": "None visited yet: fly up to a station.",
	"asteroid": "None found yet: get close to the rocks in an asteroid field.",
	"gear": "None seen yet: dock at a station (its outfitter shows every weapon and system).",
	"item": "None found yet: pick things up from wrecks, planets and markets.",
	"planet": "None visited yet: fly up to a planet or into a nebula."}

const STATION_LORE := {
	"Knossos Station": "The sector's main trade hub and home port. Busy, well defended and always hiring pilots.",
	"Helios Dock": "A shipyard built in the shadow of a gas giant. Its engineers are the best in the sector.",
	"Kephala Outpost": "A remote research outpost studying the nebulae. Pays well for rare salvage.",
	"Nyx Relay": "A communications relay on the edge of charted space. Couriers come and go at all hours.",
}

const CELESTIAL := [
	["Dikte (gas giant)", Color(0.95, 0.7, 0.45), "[b]Landable.[/b] A banded world of hydrogen and ammonia storms, far larger than any rocky planet. It has no solid surface: you land on the refinery platforms hovering in its upper clouds, metal decks linked by bridges, with the gas works' tanks, stacks and cranes - and nothing but cloud beyond the railings. Named after Mount Dikte, whose cave hid the infant Zeus from his father, the Titan Kronos - Saturn to the Romans; and like Saturn it wears bright rings.", "kronos"],
	["Amnissos (ocean world)", Color(0.25, 0.55, 0.45), "[b]Landable.[/b] Shallow seas, beaches, grassland and forest. Home to the amphibious Tritonids and a Minoan palace by the sea. Named after Amnissos, the harbour town of Knossos, where the Minoan fleets put out to sea.", "thalassa"],
	["Kamares (moon)", Color(0.6, 0.6, 0.62), "[b]Landable.[/b] Amnissos's small grey moon: regolith, rock and craters. Pale, three-eyed Selenites live around a Minoan peak palace. Named after the Kamares cave, a Minoan sanctuary high on Mount Ida.", "selene"],
	["Ida (ice world)", Color(0.85, 0.92, 1.0), "[b]Landable.[/b] Snowfields and blue ice cut by deep crevasses, with crystal spires and a Minoan palace in the ice. Named after Mount Ida, the highest peak of Crete, snow-capped half the year.", "krystallos"],
	["Akrotiri (volcanic world)", Color(0.95, 0.4, 0.1), "[b]Landable.[/b] The innermost planet, Venus-like: a scorched world of basalt and ash plains and yellow sulphur flats under a thick orange haze, crossed by rivers and lakes of glowing magma, with fumaroles, obsidian spires and the soot-blackened ruins of an older age. Named after Akrotiri, the Minoan town on Thera buried by the great eruption.", "akrotiri"],
	["Nebulae", Color(0.6, 0.3, 0.8), "Vast clouds of glowing gas lit by distant stars. Beautiful, harmless, and far behind the battlefield."],
]


## The categories: [{title, hint, entries: [entry...]}].
static func categories(tree: SceneTree) -> Array:
	var cats := []
	cats.append({"title": "Your Ship", "hint": "", "entries": [{"id": "own", "title": "Atrapos-class Light Fighter", "kind": "texture",
		"texture": tree.root.get_node("ProcArt").get_tex("ship_player"),
		"text": "Your ship: a fast, agile light fighter with twin pulse cannons and a regenerating shield.\n\n" +
			"[b]Hull[/b] 100   [b]Shields[/b] 100   [b]Speed[/b] 420\n\n" +
			"Hardpoints accept a Plasma Cannon and Missile Launcher; systems slots take an Afterburner and Shield Booster. " +
			"Research the tech tree to improve every part of it, and keep its parts in repair in the Repair Bay."}]})
	var hostiles := []
	for id in EnemyTypes.ids():
		_add(hostiles, _gated(tree, "ship:" + id, _ship_entry(id, "Hostile. Attacks you and neutral ships on sight.")))
	cats.append({"title": "Enemy Ships", "hint": HINTS["ship"], "entries": hostiles})
	var civilians := []
	for id in EnemyTypes.neutral_ids():
		_add(civilians, _gated(tree, "ship:" + id, _ship_entry(id, "Neutral. Ignores you unless you attack it, and fights back against pirates. Green shields, green minimap dot, yellow lock-on.")))
	cats.append({"title": "Neutral Ships", "hint": HINTS["ship"], "entries": civilians})
	var stations := []
	for st in tree.get_nodes_in_group("stations"):
		_add(stations, _gated(tree, "station:" + str(st.station_name), {"title": st.station_name, "kind": "station", "color": st.accent,
			"text": "%s\n\n[b]Facilities[/b]: hull repair, outfitter, cargo market, missions board.\n[b]Safe zone[/b]: enemies won't attack within the dashed ring.\n\nClick the station or press E nearby to dock." % STATION_LORE.get(st.station_name, "")}))
	cats.append({"title": "Stations", "hint": HINTS["station"], "entries": stations})
	var rocks := []
	for k in Asteroid.KINDS:
		var a: Dictionary = Asteroid.KINDS[k]
		var ore: Dictionary = Items.ITEMS[a["ore"]]
		var rarity: String = {"iron": "Common", "titanium": "Uncommon", "platinum": "Rare", "ice": "Ring"}[k]
		_add(rocks, _gated(tree, "asteroid:" + str(k), {"title": a["name"], "kind": "asteroid", "id": k, "color": a["rock"], "vein": a["vein"],
			"text": (("%s asteroid: only in planetary rings (a ringed planet's ring is a local space of its own - fly to its beacon and enter)." if k == "ice" else "%s asteroid found in the sector's asteroid fields.") + "\n\n[b]Yields[/b] %s (%d drachmas each)\n[b]Ore per rock[/b] grows with its size%s\n\nClick it to lock on: your mining beam cuts ore off it, pulled to your ship. The rock shrinks as it's mined and shatters when depleted - gone for good (mining barges work the fields too).") % [
				rarity, ore["name"], ore["value"], " (platinum rocks hold less)" if k == "platinum" else ""] + "\n\n![](shot:mining)"}))
	cats.append({"title": "Asteroids", "hint": HINTS["asteroid"], "entries": rocks})
	var weapons := []
	for id in Items.WEAPONS:
		var w: Dictionary = Items.WEAPONS[id]
		var eq: Dictionary = Items.EQUIPMENT[id]
		var cost := "Standard equipment" if eq["price"] == 0 else "%d drachmas at any station" % eq["price"]
		var ammo := "  ·  uses missiles" if w["ammo"] != "" else ""
		_add(weapons, _gated(tree, "gear:" + id, {"title": w["name"], "kind": "icon", "icon": id,
			"text": "%s\n\n[b]Damage[/b] %d   [b]Fire rate[/b] every %.2f s\n[b]Range[/b] %d%s\n\n[b]Cost[/b] %s" % [
				eq["desc"], w["damage"], w["interval"], w["range"], ammo, cost]}))
	cats.append({"title": "Weapons", "hint": HINTS["gear"], "entries": weapons})
	var systems := []
	for id in ["afterburner", "shield_booster"]:
		var eq: Dictionary = Items.EQUIPMENT[id]
		_add(systems, _gated(tree, "gear:" + id, {"title": eq["name"], "kind": "icon", "icon": id,
			"text": "%s\n\n[b]Cost[/b] %d drachmas at any station." % [eq["desc"], eq["price"]]}))
	cats.append({"title": "Systems", "hint": HINTS["gear"], "entries": systems})
	var items := []
	for id in Items.ITEMS:
		var it: Dictionary = Items.ITEMS[id]
		var price := "\n[b]Buy price[/b] %d drachmas" % it["price"] if it.has("price") else ""
		_add(items, _gated(tree, "item:" + id, {"title": it["name"], "kind": "icon", "icon": id,
			"text": "%s\n\n[b]Type[/b] %s\n[b]Sells for[/b] %d drachmas%s" % [it["desc"], it["kind"], it["value"], price]}))
	cats.append({"title": "Items", "hint": HINTS["item"], "entries": items})
	var lore := []
	var quest := tree.get_first_node_in_group("quest")
	for id in QuestData.LORE:
		var unlocked: bool = quest != null and quest.lore.has(id)
		var l: Dictionary = QuestData.LORE[id]
		if unlocked:
			lore.append({"id": "lore:" + str(id), "title": l["title"], "kind": "lore", "unlocked": true, "text": l["text"]})
		else:
			lore.append({"id": "lore:" + str(id), "title": "? ? ?", "kind": "lore", "unlocked": false,
				"text": "[i]Locked.[/i] Continue the main quest, [b]The Thread of Ariadne[/b], to unlock this entry about ancient Greece."})
	cats.append({"title": "Lore: Ancient Greece", "hint": "", "entries": lore})
	var space := []
	for c in CELESTIAL:
		var key := ("planet:" + str(c[3])) if c.size() > 3 else "nebula"
		_add(space, _gated(tree, key, {"title": c[0], "kind": "planet", "color": c[1], "text": c[2], "planet": c[3] if c.size() > 3 else ""}))
	cats.append({"title": "Celestial Bodies", "hint": HINTS["planet"], "entries": space})
	return cats


## Known: the entry (with its discovery key as its id); else {} (it isn't listed).
static func _gated(tree: SceneTree, key: String, entry: Dictionary) -> Dictionary:
	if Discovery.known(tree, key):
		entry["id"] = key
		return entry
	return {}


static func _add(list: Array, entry: Dictionary) -> void:
	if not entry.is_empty():
		list.append(entry)


static func _ship_entry(id: String, allegiance: String) -> Dictionary:
	var t := EnemyTypes.get_type(id)
	var shots := "single shots" if t["shots"] == 1 else "%d-shot spreads" % t["shots"]
	return {"title": t["name"], "kind": "texture", "texture": EnemyTypes.texture(id),
		"text": "%s\n\n[i]%s[/i]\n\n[b]Hull[/b] %d   [b]Shields[/b] %d   [b]Speed[/b] %d\n[b]Damage[/b] %d per shot, %s every %.1f s\n[b]Engagement range[/b] %d   [b]Fights at[/b] ~%d" % [
			t["desc"], allegiance, t["hull"], t["shields"], t["speed"], t["damage"], shots, t["fire_interval"], t["aggro"], t["distance"]]}


## Picture for the selected entry.
class Preview extends Control:
	var entry := {}
	var _tex: Texture2D

	func show_entry(e: Dictionary) -> void:
		entry = e
		_tex = (e["texture"] if e["texture"] is Texture2D else load(e["texture"])) if e["kind"] == "texture" else null
		# Procedural planets / rocks are child nodes with their own shaders.
		for ch in get_children():
			ch.queue_free()
		if e["kind"] == "planet" and e.get("planet", "") != "":
			var pl := Planets.make_planet(Planets.spec(e["planet"]), 210.0, 0.86 / (2.3 if e["planet"] == "kronos" else 1.0))
			pl.position = Vector2(15, 15)
			add_child(pl)
		elif e["kind"] == "asteroid":
			var rock := Asteroid.make_rock(e.get("id", "iron"), 95.0, 7, false)
			rock.position = (size / 2.0 if size.x > 0 else Vector2(120, 120)) - rock.size / 2.0
			add_child(rock)
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, NeonTheme.BG)
		draw_rect(r, Color(NeonTheme.CYAN, 0.5), false, 1.5)
		var c := size / 2.0
		match entry.get("kind", ""):
			"texture":
				var ts := _tex.get_size()
				var s := minf((size.x - 30) / ts.x, (size.y - 30) / ts.y)
				draw_texture_rect(_tex, Rect2(c - ts * s / 2.0, ts * s), false)
			"icon":
				Items.draw_icon(self, entry["icon"], r.grow(-50))
			"station":
				var col: Color = entry["color"]
				var rad := size.x * 0.32
				for side in [-1, 1]:
					draw_rect(Rect2(c + Vector2(side * rad * 0.35 if side > 0 else -rad * 1.45, -rad * 0.2), Vector2(rad * 1.1, rad * 0.4)), Color(0.12, 0.22, 0.45))
				for i in 4:
					var d := Vector2.from_angle(i * TAU / 4.0 + 0.4)
					draw_line(d * rad * 0.3 + c, d * rad * 0.9 + c, NeonTheme.TEXT_DIM, 6.0)
				draw_arc(c, rad, 0, TAU, 64, Color(0.3, 0.32, 0.37), 16.0, true)
				draw_arc(c, rad, 0, TAU, 64, NeonTheme.TEXT_DIM, 10.0, true)
				draw_circle(c, rad * 0.3, NeonTheme.TEXT_DIM)
				draw_arc(c, rad * 0.22, 0, TAU, 32, col, 3.0, true)
				draw_circle(c, rad * 0.08, col)
			"lore":
				var gold := Color(1.0, 0.82, 0.38)
				draw_arc(c, size.x * 0.4, 0, TAU, 64, Color(gold, 0.35), 2.0, true)
				preload("res://scripts/quest_beacon.gd").draw_labrys(self, c, size.x * 0.24, gold if entry.get("unlocked", false) else Color(0.4, 0.4, 0.45))
			"planet":
				if entry.get("planet", "") != "":
					return  # drawn by the procedural planet child
				var col: Color = entry["color"]
				var rad := size.x * 0.36
				draw_circle(c, rad * 1.08, Color(col, 0.15))
				draw_circle(c, rad, col.darkened(0.55))
				draw_circle(c + Vector2(-rad, -rad) * 0.12, rad * 0.88, col.darkened(0.2))
				draw_circle(c + Vector2(-rad, -rad) * 0.25, rad * 0.6, col)
