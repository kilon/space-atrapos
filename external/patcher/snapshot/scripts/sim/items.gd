class_name Items
## Catalogue of everything the player can carry, equip or use, plus the
## toolbar layout and procedurally drawn icons for all of it.

## Inventory items. kind: "cargo" (loot to sell), "ammo", "consumable".
## value = what a station pays; price = what a station charges (if sold).
const BASE_ITEMS := {
	"scrap": {
		"name": "Scrap Metal", "kind": "cargo", "value": 8,
		"desc": "Twisted hull plating. Stations buy it for recycling.",
	},
	"energy_cell": {
		"name": "Energy Cell", "kind": "cargo", "value": 15,
		"desc": "A half-charged power cell salvaged from a reactor.",
	},
	"alien_alloy": {
		"name": "Alien Alloy", "kind": "cargo", "value": 45,
		"desc": "Exotic, impossibly light metal. Worth good money.",
	},
	"cyber_matter": {
		"name": "Cybernetic Matter", "kind": "cargo", "value": 30,
		"desc": "Living circuitry from the wild beasts of the planets - half flesh, half machine. Research labs and fabricators pay for it.",
	},
	"research_data": {
		"name": "Anomaly Research Data", "kind": "cargo", "value": 260,
		"desc": "Scans of a space anomaly. Research stations pay well for it.",
	},
	"data_core": {
		"name": "Data Core", "kind": "cargo", "value": 150,
		"desc": "Encrypted navigation data. Rare and very valuable.",
	},
	"stone": {
		"name": "Building Stone", "kind": "cargo", "value": 2,
		"desc": "Rough blocks of the ground itself, cut loose by the terrain digger. Builds walls, floors and foundations.",
	},
	"iron_ore": {
		"name": "Iron Ore", "kind": "cargo", "value": 6,
		"desc": "Common ore mined from brown, rust-veined asteroids.",
	},
	"titanium_ore": {
		"name": "Titanium Ore", "kind": "cargo", "value": 16,
		"desc": "Light, strong ore from blue-grey asteroids with glowing cyan veins.",
	},
	"platinum_ore": {
		"name": "Platinum Ore", "kind": "cargo", "value": 45,
		"desc": "Rare precious ore from dark asteroids with glowing gold veins.",
	},
	# Trade goods: bought and sold at station markets (prices follow supply).
	"food": {"name": "Food", "kind": "cargo", "value": 12,
		"desc": "Hydroponic grain, protein and fruit. Agri-stations grow it; mines and military bases eat it."},
	"water": {"name": "Water", "kind": "cargo", "value": 8,
		"desc": "Purified ice water. Cheap where it's made, precious on dry mining rocks."},
	"medicine": {"name": "Medicine", "kind": "cargo", "value": 40,
		"desc": "Medical supplies from research stations. Prices soar in wartime."},
	"machinery": {"name": "Machinery", "kind": "cargo", "value": 55,
		"desc": "Drills, pumps and reactor parts from the industrial yards."},
	"electronics": {"name": "Electronics", "kind": "cargo", "value": 70,
		"desc": "Processors and sensor suites from research stations."},
	"ice": {"name": "Ring Ice", "kind": "cargo", "value": 9,
		"desc": "Water ice cut from a planetary ring - refined into water and fuel. The rings' miners live on it."},
	"fuel": {"name": "Fuel", "kind": "cargo", "value": 20,
		"desc": "Refined starship fuel. Warfleets burn through it."},
	"luxury_goods": {"name": "Luxury Goods", "kind": "cargo", "value": 95,
		"desc": "Wine, silk and art for wealthy stations - and pirate lords."},
	"weapons": {"name": "Weapons", "kind": "cargo", "value": 80,
		"desc": "Small arms and munitions. In demand wherever there is war."},
	"phaistos_fragment": {
		"name": "Disc Fragment", "kind": "quest", "value": 0,
		"desc": "A fragment of fired clay, stamped with spiralling signs like the Phaistos Disc, with a band of Linear A at its edge. Found drifting in deep space.",
	},
	# Upgrade kits (made by the ship's fabricator, fitted on its KITS page: DeviceMenu).
	"upkit_1": {"name": "Upgrade Kit Mk I", "kind": "kit", "value": 900,
		"desc": "Fits a component upgrade yourself (the Fabricator's KITS, aboard your ship): raises a stat from level 0 or 1 a level."},
	"upkit_2": {"name": "Upgrade Kit Mk II", "kind": "kit", "value": 2600,
		"desc": "Fits a component upgrade yourself (the Fabricator's KITS, aboard your ship): raises a stat from level 2 or 3 a level."},
	"upkit_3": {"name": "Upgrade Kit Mk III", "kind": "kit", "value": 6500,
		"desc": "Fits a component upgrade yourself (the Fabricator's KITS, aboard your ship): raises a stat from level 4 to the top."},
	# What the worlds' animals leave (CosmosLoot): sold at any market.
	"game_meat": {"name": "Game Meat", "kind": "cargo", "value": 11,
		"desc": "Fresh meat from a hunted beast, salted and wrapped. Towns and stations buy it for their kitchens."},
	"raw_hide": {"name": "Raw Hide", "kind": "cargo", "value": 18,
		"desc": "An untanned hide off a hunted beast. The tanners turn it into leather."},
	"beast_bone": {"name": "Beast Bones", "kind": "cargo", "value": 9,
		"desc": "Bones of a hunted beast - for glue, tools, carving and the bone-meal of the agri-domes."},
	"missile": {
		"name": "Missile", "kind": "ammo", "value": 10, "price": 20,
		"desc": "Homing missile for the Missile Launcher.",
	},
	"energy_drink": {
		"name": "Energy Drink", "kind": "consumable", "value": 12, "price": 25,
		"desc": "A fizzing can of honeyed ambrosia-cola. On foot, gives the automaton back 60 stamina (the green ring) - click it in the field inventory or put it on the toolbar.",
	},
}
## Every item: the base ones and the market's trade goods (TradeGoods).
static var ITEMS: Dictionary = BASE_ITEMS.merged(TradeGoods.GOODS)

## Takes room in the cargo hold (trade goods, ore, loot)? Credits, ammo,
## consumables and story items don't.
static func is_cargo(id: String) -> bool:
	return ITEMS.get(id, {}).get("kind", "") in ["cargo", "trade"] or Mining.is_frag(id)


## Installable equipment, bought at stations.
const EQUIPMENT := {
	"laser": {
		"name": "Pulse Cannon", "price": 0,   # (id "laser": the starting weapon)
		"desc": "Your ship's standard twin pulse cannons. Fast, accurate, unlimited - the same damage to shields and hull.",
	},
	"plasma_cannon": {
		"name": "Plasma Cannon", "price": 600,
		"desc": "Slow, heavy plasma bolts that hit almost 3x harder.",
	},
	"missile_launcher": {
		"name": "Missile Launcher", "price": 400,
		"desc": "Long-range homing missiles. Needs missile ammo.",
	},
	"afterburner": {
		"name": "Afterburner", "price": 250,
		"desc": "+80% speed for 3 seconds. 12 s cooldown.",
	},
	"shield_booster": {
		"name": "Shield Booster", "price": 350,
		"desc": "Instantly restores 60 shields. 25 s cooldown.",
	},
	"electro": {
		"name": "Electro", "price": 1600,
		"desc": "A lightning emitter: a bolt that leaps from enemy ship to enemy ship (up to 4), heavy electric damage, a chance to stun each for a moment.",
	},
	"projection_array": {
		"name": "Projection Array", "price": 2000,
		"desc": "Projects two illusions of your ship that fly beside you - enemies can't tell which is real and pick at random. An illusion vanishes when it's hit. Every few seconds your ship swaps places with one of them. 15 s; 25 s to recharge.",
	},
	"cloak": {
		"name": "Cloak", "price": 2200,
		"desc": "Switched on, your ship is half seen through and no enemy can see it - until you fire a weapon. Your shields are down while it's on; when it ends they come back to where they were in 2 seconds.",
	},
	"beam": {
		"name": "Beam Emitter", "price": 1300,
		"desc": "A continuous beam while the target's in reach: it drains shields twice as fast as its damage, and does only a third of it to a hull - strip their shields, then finish them with something else.",
	},
	"bouncer": {
		"name": "Bouncer Plasma", "price": 1500,
		"desc": "A ball of plasma that bounces from enemy to enemy (up to 6 hits, each full heat damage), then webs every ship it hit together: slowed, and unable to pull away from one another, for 6 seconds.",
	},
	"star_energizer": {
		"name": "Star Energizer", "price": 1800,
		"desc": "Refuels the ship near a star by draining its power: switch it on within reach of the sun.",
	},
	"refinery": {
		"name": "Refinery", "price": 2400,
		"desc": "An on-board ore refinery (its terminal in your ship's cargo bay): turns the fragments your mining laser cuts into minerals - a unit each, worth two and a half times as much.",
	},
	"fabricator": {
		"name": "Fabricator", "price": 3200,
		"desc": "An on-board fabricator (its terminal on your ship's bridge): makes metals, components, missiles, small weapons and Upgrade Kits from minerals and goods.",
	},
	"probe_scanner": {
		"name": "Probe Scanner", "price": 1400,
		"desc": "Scan probes launched across the system from the map (right-click empty space, or the map's PROBES): drawn tight round a signature they pin it down - anomalies, ships, planets, stations and gates. A weak signal shows only roughly where; at 100% it's located.",
	},
	"salvage_rig": {
		"name": "Salvage Rig", "price": 900,
		"desc": "Cutting arms and a tractor: salvage the wrecks destroyed ships and stations leave - scrap, parts, now and then their weapons and gear.",
	},
}

const WEAPONS := {
	"laser": {
		"name": "Pulse Cannon", "range": 650.0, "interval": 0.22, "damage": 12.0,
		"speed": 1000.0, "style": "laser", "color": Color(0.3, 0.85, 1.0), "ammo": "",
	},
	"plasma_cannon": {
		"name": "Plasma Cannon", "range": 560.0, "interval": 0.65, "damage": 34.0,
		"speed": 750.0, "style": "plasma", "color": Color(0.45, 1.0, 0.4), "ammo": "",
	},
	"missile_launcher": {
		"name": "Missiles", "range": 950.0, "interval": 0.9, "damage": 45.0,
		"speed": 520.0, "style": "missile", "color": Color(1.0, 0.6, 0.2), "ammo": "missile",
	},
	# A continuous beam (Ship._update_beam): `damage` a second while the target
	# is in range, of type "beam" (Gear.SHIELD_HULL: shields x2, hull x0.35).
	"beam": {
		"name": "Beam Emitter", "range": 540.0, "interval": 0.1, "damage": 34.0,
		"speed": 0.0, "style": "beam", "color": Color(0.5, 0.78, 1.0), "ammo": "",
	},
	# A bouncing ball of plasma (PlasmaBouncer): `bounces` hits within `leap`
	# of each other, then a web (web_time s, speed x web_slow, tether + 30 a ship).
	"bouncer": {
		"name": "Bouncer Plasma", "range": 620.0, "interval": 1.8, "damage": 16.0,
		"speed": 760.0, "style": "bouncer", "color": Color(0.45, 1.0, 0.6), "ammo": "",
		"bounces": 6, "leap": 460.0, "web_time": 6.0, "web_slow": 0.45, "tether": 220.0,
	},
	# Lightning (ChainLightning): strikes at once and leaps on to `chain` more
	# enemies within `leap`, each hit `falloff` of the last; `stun` chance.
	"electro": {
		"name": "Electro", "range": 600.0, "interval": 1.1, "damage": 30.0,
		"speed": 0.0, "style": "electro", "color": Color(0.6, 0.8, 1.0), "ammo": "",
		"chain": 3, "leap": 420.0, "falloff": 0.75, "stun": 0.25, "stun_time": 1.5,
	},
}

const SYSTEMS := {
	"afterburner": {"name": "Afterburner", "cooldown": 12.0, "duration": 3.0, "equipment": "afterburner"},
	"shield_booster": {"name": "Shield Booster", "cooldown": 25.0, "amount": 60.0, "equipment": "shield_booster"},
	# Two illusions of the ship for LIFE s (ProjectionArray).
	"projection_array": {"name": "Projection Array", "cooldown": 25.0, "equipment": "projection_array"},
	# On / off: invisible to enemies until you fire, shields down (Ship.cloak).
	"cloak": {"name": "Cloak", "cooldown": 0.3, "equipment": "cloak"},
	# On / off: near a star, refuels the ship (Ship._update_energizer).
	"star_energizer": {"name": "Star Energizer", "cooldown": 0.5, "equipment": "star_energizer"},
}

## (The toolbars: Inventory.SHIP_TOOLBAR / FOOT_TOOLBAR, filled by the player.)


## A stack's tooltip: its name and count, what it is, what it sells for and
## `hint` (what clicking / dragging it does here).
static func tooltip(id: String, n: int, hint := "") -> String:
	var it: Dictionary = info(id)
	if it.is_empty():
		return id
	var t := "%s  ×%d\n%s" % [it.get("name", id), n, it.get("desc", "")]
	if Gear.is_gear(id):
		t += "\n" + Gear.describe(id)
	elif Hardpoints.is_weapon(id):
		t += "\n" + Hardpoints.describe(id)
	t += "\n" + ("Main quest item - cannot be sold." if it.get("kind", "") == "quest" else "Sells for %d drachmas each." % int(it.get("value", 0)))
	if hint != "":
		t += "\n" + hint
	return t


## An item's data ({name, kind, value, desc...}): the catalogue's, or a gear
## item's (Gear: "gear:<kind>:<quality>") - {} if there's no such item.
static func info(id: String) -> Dictionary:
	if ITEMS.has(id):
		return ITEMS[id]
	if Gear.is_gear(id):
		return Gear.info(id)
	if Hardpoints.is_weapon(id):
		return Hardpoints.info(id)
	if Mining.is_frag(id):
		return Mining.info(id)
	if NavReports.is_report(id):
		return NavReports.info(id)
	if Skills.is_skill(id):
		return Skills.info(id)
	if Inventory.is_tool_id(id):
		return {"name": Inventory.TOOLS[id]["name"], "kind": "tool", "value": 0, "desc": Inventory.TOOLS[id]["desc"]}
	return {}


## Whether `id` is a known item (the catalogue's or a piece of gear).
static func exists(id: String) -> bool:
	return ITEMS.has(id) or not Gear.parse(id).is_empty() or not Hardpoints.parse(id).is_empty() or Mining.valid(id) or NavReports.valid(id) or Skills.valid(id)


static func display_name(id: String) -> String:
	if id == "credits":
		return "Drachmas"
	if Gear.is_gear(id):
		return Gear.title(id)
	if Hardpoints.is_weapon(id):
		return Hardpoints.title(id)
	if Mining.is_frag(id):
		return str(Mining.info(id).get("name", id))
	if NavReports.is_report(id):
		return str(NavReports.info(id).get("name", id))
	if Skills.is_skill(id):
		return str(Skills.info(id).get("name", id))
	if Inventory.is_tool_id(id):
		return str(Inventory.TOOLS[id]["name"])
	if ITEMS.has(id):
		return ITEMS[id]["name"]
	if EQUIPMENT.has(id):
		return EQUIPMENT[id]["name"]
	return id


# --- Icons -------------------------------------------------------------------
# Each icon is drawn once into a small texture (icon_texture: off screen, a
# SubViewport) and the inventories' slots draw that: a page of slots (the
# outfitter's 70 cards) costs one draw call a slot instead of half a dozen.
# Until a texture is ready - and with no renderer (headless) - the slots draw
# the icon itself (draw_icon).

const ICON_BAKE := 64
static var _icon_tex := {}         # "id|dim" -> Texture2D, or null while baking / when it can't be
static var _icon_queue: Array = []
static var _icon_baking := false


class IconDraw extends Control:
	var id := ""
	var dim := false
	func _draw() -> void:
		Items.draw_icon(self, id, Rect2(Vector2.ZERO, size), dim)


static func icon_texture(id: String, dim := false) -> Texture2D:
	var key := "%s|%s" % [id, dim]
	if _icon_tex.has(key):
		return _icon_tex[key]
	_icon_tex[key] = null
	_icon_queue.append([key, id, dim])
	if not _icon_baking:
		_bake_icons.call_deferred()
	return null


static func _bake_icons() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or _icon_queue.is_empty():
		return
	_icon_baking = true
	# A few at a time (a screen full of new icons at once - 18 viewports and
	# read-backs in one frame - was a long frame); the rest in the next batch.
	var jobs := _icon_queue.slice(0, 4)
	_icon_queue = _icon_queue.slice(4)
	var vps := []
	for j in jobs:
		var vp := SubViewport.new()
		vp.size = Vector2i(ICON_BAKE, ICON_BAKE)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var d := IconDraw.new()
		d.id = j[1]
		d.dim = j[2]
		d.size = Vector2(ICON_BAKE, ICON_BAKE)
		vp.add_child(d)
		tree.root.add_child(vp)
		vps.append(vp)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for i in jobs.size():
		var img: Image = vps[i].get_texture().get_image()
		vps[i].queue_free()
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			_icon_tex[jobs[i][0]] = ImageTexture.create_from_image(img)
	_icon_baking = false
	tree.call_group("item_slots", "queue_redraw")
	if not _icon_queue.is_empty():
		_bake_icons()

## The automaton's tools (Inventory.TOOLS): the rifle, the mining beam's
## cutting ray, the digger's bit, the scanner's rings.
static func _tool_icon(ci: CanvasItem, id: String, rect: Rect2, dim: bool) -> void:
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) / 2.0
	var a := 0.35 if dim else 1.0
	var metal := Color(0.78, 0.8, 0.86, a)
	var glow := Color(0.45, 1.0, 1.0, a)
	match id:
		"tool:rifle":
			ci.draw_line(c + Vector2(-0.75, 0.1) * s, c + Vector2(0.75, -0.2) * s, metal, s * 0.2, true)
			ci.draw_line(c + Vector2(-0.75, 0.1) * s, c + Vector2(-0.8, 0.45) * s, metal, s * 0.22, true)
			ci.draw_line(c + Vector2(-0.15, 0.0) * s, c + Vector2(-0.25, 0.5) * s, metal, s * 0.14, true)
			ci.draw_circle(c + Vector2(0.8, -0.21) * s, s * 0.1, Color(1.0, 0.6, 0.25, a))
		"tool:beam":
			ci.draw_line(c + Vector2(-0.75, 0.55) * s, c + Vector2(0.35, -0.35) * s, Color(glow, 0.35 * a), s * 0.32, true)
			ci.draw_line(c + Vector2(-0.75, 0.55) * s, c + Vector2(0.35, -0.35) * s, glow, s * 0.1, true)
			var hit := c + Vector2(0.45, -0.45) * s
			ci.draw_colored_polygon(PackedVector2Array([hit + Vector2(0, -0.32) * s, hit + Vector2(0.28, 0.05) * s,
				hit + Vector2(0.02, 0.3) * s, hit + Vector2(-0.26, 0.02) * s]), Color(0.7, 0.45, 0.9, a))
			for k in 4:
				var d := Vector2.from_angle(TAU * k / 4.0 + 0.4)
				ci.draw_line(hit + d * s * 0.36, hit + d * s * 0.55, glow, s * 0.06, true)
		"tool:digger":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.35, -0.7) * s, c + Vector2(0.35, -0.7) * s,
				c + Vector2(0.0, 0.55) * s]), metal)
			for k in 3:
				var y := -0.45 + k * 0.3
				var w := 0.35 * (0.55 - y) / 1.25
				ci.draw_line(c + Vector2(-w, y) * s, c + Vector2(w, y + 0.12) * s, Color(0.35, 0.38, 0.45, a), s * 0.07, true)
			ci.draw_arc(c + Vector2(0, 0.75) * s, s * 0.45, PI * 1.1, PI * 1.9, 12, Color(0.75, 0.55, 0.3, a), s * 0.1, true)
		"tool:build":   # (a wall of blocks and a trowel)
			for row in 3:
				for k in 3 - row % 2:
					var x0 := -0.75 + k * 0.5 + (0.25 if row % 2 else 0.0)
					ci.draw_rect(Rect2(c + Vector2(x0, 0.3 - row * 0.32) * s, Vector2(0.46, 0.28) * s), Color(0.82, 0.74, 0.6, a))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.15, -0.55) * s, c + Vector2(0.75, -0.75) * s, c + Vector2(0.55, -0.35) * s]), metal)
			ci.draw_line(c + Vector2(0.45, -0.5) * s, c + Vector2(0.8, -0.2) * s, Color(0.55, 0.35, 0.2, a), s * 0.12, true)
		"tool:scanner":
			for k in 3:
				ci.draw_arc(c + Vector2(0, 0.45) * s, s * (0.3 + k * 0.28), PI * 1.15, PI * 1.85, 16, Color(glow, a * (1.0 - k * 0.25)), s * 0.09, true)
			ci.draw_circle(c + Vector2(0, 0.45) * s, s * 0.14, glow)


## Draws the icon for `id` inside `rect` on any CanvasItem (call from _draw).
static func draw_icon(ci: CanvasItem, id: String, rect: Rect2, dim := false) -> void:
	if Gear.is_gear(id):
		Gear.draw_icon(ci, id, rect, dim)
		return
	if Hardpoints.is_weapon(id):
		Hardpoints.draw_icon(ci, id, rect, dim)
		return
	if Mining.is_frag(id):
		Mining.draw_icon(ci, id, rect, dim)
		return
	if NavReports.is_report(id):
		NavReports.draw_icon(ci, id, rect, dim)
		return
	if Skills.is_skill(id):
		Skills.draw_icon(ci, id, rect, dim)
		return
	if TradeGoods.GOODS.has(id):
		TradeGoods.draw_icon(ci, id, rect, dim)
		return
	if Inventory.is_tool_id(id):
		_tool_icon(ci, id, rect, dim)
		return
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) / 2.0
	var a := 0.35 if dim else 1.0

	match id:
		"laser":
			var p0 := c + Vector2(-0.7, 0.7) * s
			var p1 := c + Vector2(0.7, -0.7) * s
			ci.draw_line(p0, p1, Color(0.3, 0.85, 1.0, 0.35 * a), s * 0.4, true)
			ci.draw_line(p0, p1, Color(0.8, 0.97, 1.0, a), s * 0.12, true)
			ci.draw_circle(p0, s * 0.18, Color(0.6, 0.65, 0.7, a))
		"plasma_cannon":
			ci.draw_circle(c, s * 0.7, Color(0.4, 1.0, 0.4, 0.2 * a))
			ci.draw_circle(c, s * 0.48, Color(0.45, 1.0, 0.45, 0.6 * a))
			ci.draw_circle(c, s * 0.28, Color(0.85, 1.0, 0.8, a))
			ci.draw_arc(c, s * 0.75, 0, TAU, 24, Color(0.5, 1.0, 0.5, 0.7 * a), 2.0, true)
		"missile_launcher", "missile":
			var d := Vector2(1, -1).normalized()
			var n := d.orthogonal()
			var w := s * 0.16
			var tail := c - d * s * 0.6
			var head := c + d * s * 0.42
			ci.draw_colored_polygon(PackedVector2Array([
				tail - n * s * 0.32, tail + d * s * 0.3, tail + n * s * 0.32]), Color(0.85, 0.25, 0.2, a))
			ci.draw_colored_polygon(PackedVector2Array([
				tail + n * w, head + n * w, head - n * w, tail - n * w]), Color(0.88, 0.9, 0.92, a))
			ci.draw_colored_polygon(PackedVector2Array([
				head + n * w, c + d * s * 0.78, head - n * w]), Color(0.9, 0.25, 0.2, a))
			ci.draw_circle(tail - d * s * 0.12, s * 0.13, Color(1.0, 0.65, 0.2, 0.9 * a))
		"afterburner":
			var outer := PackedVector2Array([
				c + Vector2(0, -0.85) * s, c + Vector2(0.55, 0.15) * s, c + Vector2(0.32, 0.75) * s,
				c + Vector2(-0.32, 0.75) * s, c + Vector2(-0.55, 0.15) * s])
			var inner := PackedVector2Array([
				c + Vector2(0, -0.35) * s, c + Vector2(0.28, 0.3) * s, c + Vector2(0, 0.7) * s,
				c + Vector2(-0.28, 0.3) * s])
			ci.draw_colored_polygon(outer, Color(1.0, 0.45, 0.1, a))
			ci.draw_colored_polygon(inner, Color(1.0, 0.9, 0.4, a))
		"shield_booster":
			var shield := PackedVector2Array([
				c + Vector2(-0.6, -0.65) * s, c + Vector2(0.6, -0.65) * s, c + Vector2(0.6, 0.0) * s,
				c + Vector2(0, 0.8) * s, c + Vector2(-0.6, 0.0) * s])
			ci.draw_colored_polygon(shield, Color(0.3, 0.75, 1.0, 0.35 * a))
			ci.draw_polyline(_closed(shield), Color(0.5, 0.9, 1.0, a), 2.0, true)
			ci.draw_line(c + Vector2(-0.25, -0.05) * s, c + Vector2(0.25, -0.05) * s, Color(1, 1, 1, a), 3.0)
			ci.draw_line(c + Vector2(0, -0.3) * s, c + Vector2(0, 0.2) * s, Color(1, 1, 1, a), 3.0)
		"ice":   # (a pale-blue crystal of ring ice)
			var shard := PackedVector2Array([c + Vector2(0, -0.85) * s, c + Vector2(0.55, -0.2) * s, c + Vector2(0.4, 0.7) * s,
				c + Vector2(-0.4, 0.7) * s, c + Vector2(-0.55, -0.2) * s])
			ci.draw_colored_polygon(shard, Color(0.7, 0.88, 1.0, a))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.85) * s, c + Vector2(0.18, 0.1) * s, c + Vector2(-0.4, 0.7) * s,
				c + Vector2(-0.55, -0.2) * s]), Color(0.92, 0.98, 1.0, a))
			ci.draw_polyline(_closed(shard), Color(0.4, 0.7, 1.0, a), 1.5, true)
		"electro":
			var bolt := PackedVector2Array([c + Vector2(0.15, -0.85) * s, c + Vector2(-0.35, 0.05) * s, c + Vector2(0.05, 0.05) * s,
				c + Vector2(-0.2, 0.85) * s, c + Vector2(0.45, -0.15) * s, c + Vector2(0.05, -0.15) * s])
			ci.draw_circle(c, s * 0.8, Color(0.5, 0.7, 1.0, 0.18 * a))
			ci.draw_colored_polygon(bolt, Color(0.75, 0.88, 1.0, a))
			ci.draw_polyline(_closed(bolt), Color(0.4, 0.6, 1.0, a), 1.5, true)
		"projection_array":
			# Three ship shapes: one solid, two faint copies beside it.
			for k in [-1, 1, 0]:
				var o := Vector2(k * 0.5, 0.1 * absf(k)) * s
				var tri := PackedVector2Array([c + o + Vector2(0, -0.55) * s, c + o + Vector2(0.28, 0.45) * s, c + o + Vector2(-0.28, 0.45) * s])
				ci.draw_colored_polygon(tri, Color(0.7, 0.88, 1.0, (1.0 if k == 0 else 0.35) * a))
		"cloak":
			# A ship's outline, dashed and fading.
			var hull := PackedVector2Array([c + Vector2(0, -0.8) * s, c + Vector2(0.55, 0.6) * s, c + Vector2(0, 0.3) * s, c + Vector2(-0.55, 0.6) * s])
			ci.draw_colored_polygon(hull, Color(0.6, 0.75, 0.95, 0.18 * a))
			for i in 4:
				var p0: Vector2 = hull[i]
				var p1: Vector2 = hull[(i + 1) % 4]
				ci.draw_line(p0, p0.lerp(p1, 0.45), Color(0.75, 0.88, 1.0, a), 2.0, true)
				ci.draw_line(p0.lerp(p1, 0.65), p1, Color(0.75, 0.88, 1.0, 0.5 * a), 2.0, true)
		"beam":
			ci.draw_rect(Rect2(c + Vector2(-0.75, -0.2) * s, Vector2(0.45, 0.4) * s), Color(0.7, 0.72, 0.78, a))
			ci.draw_line(c + Vector2(-0.3, 0) * s, c + Vector2(0.8, 0) * s, Color(0.5, 0.78, 1.0, 0.4 * a), s * 0.32, true)
			ci.draw_line(c + Vector2(-0.3, 0) * s, c + Vector2(0.8, 0) * s, Color(0.85, 0.95, 1.0, a), s * 0.1, true)
			ci.draw_circle(c + Vector2(0.8, 0) * s, s * 0.14, Color(0.7, 0.9, 1.0, a))
		"bouncer":
			# Three linked plasma balls.
			var pts := [c + Vector2(-0.5, 0.35) * s, c + Vector2(0.0, -0.5) * s, c + Vector2(0.5, 0.35) * s]
			for i in 3:
				ci.draw_line(pts[i], pts[(i + 1) % 3], Color(0.45, 1.0, 0.6, 0.7 * a), 2.0, true)
			for p in pts:
				ci.draw_circle(p, s * 0.26, Color(0.45, 1.0, 0.6, 0.35 * a))
				ci.draw_circle(p, s * 0.15, Color(0.85, 1.0, 0.9, a))
		"star_energizer":
			ci.draw_circle(c + Vector2(-0.35, -0.35) * s, s * 0.38, Color(1.0, 0.75, 0.25, a))
			ci.draw_circle(c + Vector2(-0.35, -0.35) * s, s * 0.55, Color(1.0, 0.6, 0.2, 0.25 * a))
			for k in 3:
				var o := Vector2(k - 1, 1 - k).normalized() * 0.0 + Vector2(0.1 * (k - 1), -0.1 * (k - 1)) * s
				ci.draw_line(c + Vector2(-0.05, -0.05) * s + o, c + Vector2(0.45, 0.45) * s + o, Color(1.0, 0.85, 0.4, a), 2.0, true)
			ci.draw_rect(Rect2(c + Vector2(0.3, 0.3) * s, Vector2(0.4, 0.4) * s), Color(0.7, 0.72, 0.78, a))
		"refinery":   # a crucible pouring
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.55, -0.45) * s, c + Vector2(0.55, -0.45) * s, c + Vector2(0.35, 0.35) * s, c + Vector2(-0.35, 0.35) * s]), Color(0.42, 0.44, 0.48, a))
			ci.draw_rect(Rect2(c + Vector2(-0.45, -0.38) * s, Vector2(0.9, 0.25) * s), Color(1.0, 0.55, 0.15, a))
			ci.draw_line(c + Vector2(0.5, -0.3) * s, c + Vector2(0.7, 0.6) * s, Color(1.0, 0.7, 0.25, a), s * 0.12, true)
			ci.draw_rect(Rect2(c + Vector2(-0.6, 0.45) * s, Vector2(1.2, 0.18) * s), Color(0.3, 0.32, 0.36, a))
		"fabricator":   # a gear under a press
			ci.draw_rect(Rect2(c + Vector2(-0.6, -0.7) * s, Vector2(1.2, 0.22) * s), Color(0.45, 0.47, 0.52, a))
			ci.draw_line(c + Vector2(0, -0.48) * s, c + Vector2(0, -0.1) * s, Color(0.7, 0.72, 0.76, a), s * 0.16, true)
			for k in 8:
				var ga := TAU * k / 8.0
				ci.draw_line(c + Vector2(0, 0.3) * s + Vector2.from_angle(ga) * s * 0.3, c + Vector2(0, 0.3) * s + Vector2.from_angle(ga) * s * 0.48, Color(0.4, 0.85, 1.0, a), s * 0.12, true)
			ci.draw_circle(c + Vector2(0, 0.3) * s, s * 0.32, Color(0.4, 0.85, 1.0, a))
			ci.draw_circle(c + Vector2(0, 0.3) * s, s * 0.12, Color(0.1, 0.12, 0.15, a))
		"upkit_1", "upkit_2", "upkit_3":   # a case with an arrow up, its mark's pips
			var case := Rect2(c + Vector2(-0.6, -0.45) * s, Vector2(1.2, 0.95) * s)
			ci.draw_rect(case, Color(0.2, 0.22, 0.26, a))
			ci.draw_rect(case, Color(1.0, 0.75, 0.3, a), false, maxf(1.5, s * 0.08))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.32) * s, c + Vector2(0.28, 0.02) * s, c + Vector2(-0.28, 0.02) * s]), Color(0.45, 1.0, 0.55, a))
			ci.draw_rect(Rect2(c + Vector2(-0.1, 0.0) * s, Vector2(0.2, 0.3) * s), Color(0.45, 1.0, 0.55, a))
			for k in int(id.right(1)):
				ci.draw_circle(c + Vector2(-0.4 + k * 0.2, 0.62) * s, s * 0.07, Color(1.0, 0.8, 0.35, a))
		"probe_scanner":   # a probe: a body with fins, and its reach in rings
			for i in 3:
				ci.draw_arc(c, s * (0.35 + 0.22 * i), -2.4, -0.7, 10, Color(0.55, 0.85, 1.0, a * (0.9 - 0.25 * i)), 1.6, true)
			ci.draw_circle(c + Vector2(0, 0.25) * s, s * 0.2, Color(0.75, 0.78, 0.82, a))
			ci.draw_line(c + Vector2(0, 0.25) * s, c + Vector2(0, 0.75) * s, Color(0.75, 0.78, 0.82, a), s * 0.12, true)
			ci.draw_circle(c + Vector2(0, 0.25) * s, s * 0.08, Color(1.0, 0.6, 0.2, a))
		"salvage_rig":
			ci.draw_line(c + Vector2(-0.7, 0.6) * s, c + Vector2(0.0, -0.2) * s, Color(0.75, 0.77, 0.8, a), s * 0.18, true)
			ci.draw_line(c + Vector2(0.0, -0.2) * s, c + Vector2(0.55, 0.15) * s, Color(0.75, 0.77, 0.8, a), s * 0.14, true)
			ci.draw_arc(c + Vector2(0.55, 0.15) * s, s * 0.22, -1.2, 2.2, 10, Color(1.0, 0.7, 0.25, a), 2.5, true)
			ci.draw_circle(c + Vector2(0.0, -0.2) * s, s * 0.12, Color(1.0, 0.7, 0.25, a))
		"energy_drink":
			var can := Rect2(c - Vector2(0.38, 0.62) * s, Vector2(0.76, 1.24) * s)
			ci.draw_rect(can, Color(0.25, 0.75, 0.3, a))
			ci.draw_rect(Rect2(can.position, Vector2(can.size.x, s * 0.14)), Color(0.8, 0.84, 0.88, a))
			ci.draw_rect(Rect2(can.position + Vector2(0, can.size.y - s * 0.12), Vector2(can.size.x, s * 0.12)), Color(0.8, 0.84, 0.88, a))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.08, -0.4) * s, c + Vector2(-0.2, 0.06) * s, c + Vector2(0.0, 0.06) * s,
				c + Vector2(-0.08, 0.42) * s, c + Vector2(0.22, -0.08) * s, c + Vector2(0.02, -0.08) * s]), Color(1.0, 0.9, 0.3, a))
			ci.draw_rect(can, Color(0.65, 1.0, 0.6, a), false, maxf(1.0, s * 0.06))
		"scrap":
			var pts := PackedVector2Array()
			for v in [Vector2(-0.6, -0.2), Vector2(-0.2, -0.65), Vector2(0.3, -0.45), Vector2(0.65, 0.05),
					Vector2(0.35, 0.6), Vector2(-0.25, 0.55), Vector2(-0.6, 0.3)]:
				pts.append(c + v * s)
			ci.draw_colored_polygon(pts, Color(0.55, 0.57, 0.6, a))
			ci.draw_polyline(_closed(pts), Color(0.8, 0.82, 0.85, a), 1.5, true)
			ci.draw_line(c + Vector2(-0.3, -0.1) * s, c + Vector2(0.3, 0.2) * s, Color(0.35, 0.36, 0.4, a), 2.0)
		"energy_cell":
			ci.draw_rect(Rect2(c + Vector2(-0.38, -0.5) * s, Vector2(0.76, 1.15) * s), Color(0.95, 0.8, 0.2, a))
			ci.draw_rect(Rect2(c + Vector2(-0.16, -0.68) * s, Vector2(0.32, 0.18) * s), Color(0.7, 0.7, 0.72, a))
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.08, -0.35) * s, c + Vector2(-0.18, 0.1) * s, c + Vector2(0.02, 0.1) * s,
				c + Vector2(-0.08, 0.5) * s, c + Vector2(0.2, -0.02) * s, c + Vector2(0.0, -0.02) * s]),
				Color(0.3, 0.2, 0.05, a))
		"alien_alloy":
			var hex := PackedVector2Array()
			var hex_in := PackedVector2Array()
			for i in 6:
				var ang := TAU * i / 6.0 + PI / 6.0
				hex.append(c + Vector2.from_angle(ang) * s * 0.72)
				hex_in.append(c + Vector2.from_angle(ang) * s * 0.4)
			ci.draw_colored_polygon(hex, Color(0.55, 0.25, 0.8, a))
			ci.draw_colored_polygon(hex_in, Color(0.85, 0.6, 1.0, a))
			ci.draw_polyline(_closed(hex), Color(0.9, 0.75, 1.0, a), 1.5, true)
		"cyber_matter":   # (a glowing node with circuit tendrils)
			for k in 5:
				var d := Vector2.from_angle(TAU * k / 5.0 - PI / 2.0)
				ci.draw_line(c + d * s * 0.2, c + d * s * 0.72, Color(0.3, 0.9, 0.85, a), 2.0, true)
				ci.draw_circle(c + d * s * 0.72, s * 0.11, Color(0.6, 1.0, 0.95, a))
			ci.draw_circle(c, s * 0.34, Color(0.12, 0.45, 0.5, a))
			ci.draw_circle(c, s * 0.2, Color(0.7, 1.0, 0.95, a))
		"data_core":
			var dia := PackedVector2Array([c + Vector2(0, -0.8) * s, c + Vector2(0.55, 0) * s,
				c + Vector2(0, 0.8) * s, c + Vector2(-0.55, 0) * s])
			var dia_in := PackedVector2Array([c + Vector2(0, -0.4) * s, c + Vector2(0.27, 0) * s,
				c + Vector2(0, 0.4) * s, c + Vector2(-0.27, 0) * s])
			ci.draw_colored_polygon(dia, Color(0.15, 0.6, 0.8, a))
			ci.draw_colored_polygon(dia_in, Color(0.8, 1.0, 1.0, a))
			ci.draw_polyline(_closed(dia), Color(0.6, 0.95, 1.0, a), 1.5, true)
		"iron_ore", "titanium_ore", "platinum_ore":
			var cols := {"iron_ore": [Color(0.5, 0.43, 0.37), Color(0.9, 0.5, 0.3)],
				"titanium_ore": [Color(0.42, 0.46, 0.52), Color(0.45, 0.9, 1.0)],
				"platinum_ore": [Color(0.34, 0.32, 0.35), Color(1.0, 0.85, 0.4)]}
			var rock: Color = cols[id][0]
			var vein: Color = cols[id][1]
			var nug := PackedVector2Array()
			for v in [Vector2(-0.65, -0.1), Vector2(-0.3, -0.6), Vector2(0.25, -0.55), Vector2(0.65, -0.1),
					Vector2(0.5, 0.45), Vector2(-0.05, 0.62), Vector2(-0.55, 0.4)]:
				nug.append(c + v * s)
			ci.draw_colored_polygon(nug, Color(rock, a))
			ci.draw_polyline(_closed(nug), Color(rock.lightened(0.35), a), 1.5, true)
			for v in [Vector2(-0.25, -0.2), Vector2(0.2, 0.05), Vector2(-0.05, 0.35), Vector2(0.3, -0.3)]:
				ci.draw_circle(c + v * s, s * 0.11, Color(vein, a))
		"phaistos_fragment":
			var clay := Color(0.78, 0.45, 0.28)
			var frag := PackedVector2Array()
			for k in 9:
				var ang := -0.4 + k * 0.42
				frag.append(c + Vector2.from_angle(ang) * s * 0.75)
			frag.append(c + Vector2(-0.1, 0.05) * s)
			ci.draw_colored_polygon(frag, Color(clay, a))
			ci.draw_polyline(_closed(frag), Color(clay.darkened(0.4), a), 1.5, true)
			for k in 7:
				var t := k / 7.0
				var p := c + Vector2.from_angle(0.2 + t * 2.6) * s * (0.6 - 0.35 * t)
				ci.draw_circle(p, s * 0.07, Color(clay.darkened(0.5), a))
		"food":
			ci.draw_circle(c + Vector2(-0.18, 0.12) * s, s * 0.42, Color(0.85, 0.25, 0.2, a))
			ci.draw_circle(c + Vector2(0.25, 0.18) * s, s * 0.36, Color(0.95, 0.75, 0.2, a))
			ci.draw_line(c + Vector2(-0.15, -0.3) * s, c + Vector2(0.0, -0.65) * s, Color(0.4, 0.8, 0.3, a), 3.0)
			ci.draw_circle(c + Vector2(-0.3, 0.0) * s, s * 0.1, Color(1, 1, 1, 0.5 * a))
		"water":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.8) * s, c + Vector2(0.5, 0.15) * s, c + Vector2(0.35, 0.6) * s,
				c + Vector2(0, 0.72) * s, c + Vector2(-0.35, 0.6) * s, c + Vector2(-0.5, 0.15) * s]), Color(0.3, 0.65, 1.0, a))
			ci.draw_circle(c + Vector2(-0.15, 0.25) * s, s * 0.12, Color(0.85, 0.95, 1.0, a))
		"medicine":
			ci.draw_rect(Rect2(c - Vector2(0.62, 0.45) * s, Vector2(1.24, 0.9) * s), Color(0.92, 0.94, 0.96, a))
			ci.draw_rect(Rect2(c - Vector2(0.1, 0.32) * s, Vector2(0.2, 0.64) * s), Color(0.9, 0.2, 0.2, a))
			ci.draw_rect(Rect2(c - Vector2(0.32, 0.1) * s, Vector2(0.64, 0.2) * s), Color(0.9, 0.2, 0.2, a))
		"machinery":
			for k in 8:
				var ang := TAU * k / 8.0
				ci.draw_line(c + Vector2.from_angle(ang) * s * 0.4, c + Vector2.from_angle(ang) * s * 0.72, Color(0.6, 0.62, 0.68, a), s * 0.22)
			ci.draw_circle(c, s * 0.48, Color(0.55, 0.57, 0.62, a))
			ci.draw_circle(c, s * 0.18, Color(0.2, 0.2, 0.24, a))
		"electronics":
			ci.draw_rect(Rect2(c - Vector2(0.45, 0.45) * s, Vector2(0.9, 0.9) * s), Color(0.1, 0.45, 0.25, a))
			for k in 4:
				var y := -0.3 + k * 0.2
				ci.draw_line(c + Vector2(-0.7, y) * s, c + Vector2(-0.45, y) * s, Color(0.9, 0.8, 0.4, a), 2.0)
				ci.draw_line(c + Vector2(0.45, y) * s, c + Vector2(0.7, y) * s, Color(0.9, 0.8, 0.4, a), 2.0)
			ci.draw_rect(Rect2(c - Vector2(0.2, 0.2) * s, Vector2(0.4, 0.4) * s), Color(0.15, 0.15, 0.18, a))
		"fuel":
			ci.draw_rect(Rect2(c - Vector2(0.4, 0.55) * s, Vector2(0.8, 1.2) * s), Color(0.85, 0.35, 0.15, a))
			ci.draw_rect(Rect2(c + Vector2(0.05, -0.75) * s, Vector2(0.25, 0.2) * s), Color(0.6, 0.6, 0.65, a))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -0.25) * s, c + Vector2(0.2, 0.2) * s, c + Vector2(0, 0.4) * s, c + Vector2(-0.2, 0.2) * s]), Color(1.0, 0.85, 0.3, a))
		"luxury_goods":
			var gem := PackedVector2Array([c + Vector2(-0.6, -0.2) * s, c + Vector2(-0.3, -0.55) * s, c + Vector2(0.3, -0.55) * s,
				c + Vector2(0.6, -0.2) * s, c + Vector2(0, 0.7) * s])
			ci.draw_colored_polygon(gem, Color(0.95, 0.35, 0.75, a))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.3, -0.2) * s, c + Vector2(0.3, -0.2) * s, c + Vector2(0, 0.5) * s]), Color(1.0, 0.7, 0.9, a))
			ci.draw_polyline(_closed(gem), Color(1.0, 0.85, 0.95, a), 1.5, true)
		"weapons":
			ci.draw_rect(Rect2(c - Vector2(0.7, 0.4) * s, Vector2(1.4, 0.85) * s), Color(0.32, 0.36, 0.28, a))
			ci.draw_rect(Rect2(c - Vector2(0.7, 0.4) * s, Vector2(1.4, 0.85) * s), Color(0.6, 0.65, 0.5, a), false, 2.0)
			ci.draw_line(c + Vector2(-0.45, 0.0) * s, c + Vector2(0.45, 0.0) * s, Color(0.95, 0.75, 0.2, a), s * 0.16)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.45, -0.15) * s, c + Vector2(0.62, 0.0) * s, c + Vector2(0.45, 0.15) * s]), Color(0.95, 0.75, 0.2, a))
		"research_data":   # a data slate with a swirl of the anomaly on it
			ci.draw_rect(Rect2(c - Vector2(0.5, 0.65) * s, Vector2(1.0, 1.3) * s), Color(0.14, 0.2, 0.32, a))
			ci.draw_rect(Rect2(c - Vector2(0.5, 0.65) * s, Vector2(1.0, 1.3) * s), Color(0.55, 0.8, 1.0, a), false, 2.0)
			for k in 3:
				ci.draw_arc(c + Vector2(0, -0.1) * s, s * (0.12 + k * 0.1), k * 1.4, k * 1.4 + PI * 1.2, 12, Color(0.6, 0.9, 1.0, a), 1.5, true)
			ci.draw_line(c + Vector2(-0.3, 0.45) * s, c + Vector2(0.3, 0.45) * s, Color(0.55, 0.8, 1.0, a), 1.5)
		"stone":   # (three rough blocks)
			for b in [[Vector2(-0.7, 0.05), Vector2(0.7, 0.55)], [Vector2(0.05, 0.05), Vector2(0.65, 0.55)], [Vector2(-0.35, -0.5), Vector2(0.7, 0.55)]]:
				var o: Vector2 = b[0]
				var sz: Vector2 = b[1]
				ci.draw_rect(Rect2(c + o * s, sz * s), Color(0.62, 0.6, 0.56, a))
				ci.draw_rect(Rect2(c + o * s, sz * s), Color(0.3, 0.29, 0.27, a), false, 1.5)
		"game_meat":   # (a joint of meat, its bone)
			ci.draw_line(c + Vector2(0.25, -0.25) * s, c + Vector2(0.72, -0.72) * s, Color(0.92, 0.88, 0.8, a), s * 0.16, true)
			ci.draw_circle(c + Vector2(0.75, -0.75) * s, s * 0.12, Color(0.92, 0.88, 0.8, a))
			ci.draw_circle(c + Vector2(-0.12, 0.12) * s, s * 0.52, Color(0.62, 0.16, 0.12, a))
			ci.draw_circle(c + Vector2(-0.18, 0.18) * s, s * 0.32, Color(0.82, 0.32, 0.26, a))
		"raw_hide":    # (a stretched hide)
			var hide := PackedVector2Array()
			for k in 12:
				var ang := TAU * k / 12.0
				var rr := (0.72 if k % 3 == 0 else 0.55) * s
				hide.append(c + Vector2(cos(ang), sin(ang) * 0.8) * rr)
			ci.draw_colored_polygon(hide, Color(0.58, 0.4, 0.25, a))
			ci.draw_polyline(_closed(hide), Color(0.3, 0.18, 0.1, a), 1.5, true)
			ci.draw_circle(c, s * 0.2, Color(0.68, 0.5, 0.33, a))
		"beast_bone":  # (two crossed bones)
			for dd in [Vector2(0.62, 0.62), Vector2(0.62, -0.62)]:
				ci.draw_line(c - dd * s, c + dd * s, Color(0.9, 0.86, 0.76, a), s * 0.18, true)
				for e in [-1.0, 1.0]:
					ci.draw_circle(c + dd * s * e + Vector2(dd.y, -dd.x).normalized() * s * 0.1, s * 0.12, Color(0.9, 0.86, 0.76, a))
					ci.draw_circle(c + dd * s * e - Vector2(dd.y, -dd.x).normalized() * s * 0.1, s * 0.12, Color(0.9, 0.86, 0.76, a))
		"credits":
			ci.draw_circle(c, s * 0.62, Color(0.75, 0.55, 0.1, a))
			ci.draw_circle(c, s * 0.52, Color(1.0, 0.82, 0.3, a))
			ci.draw_arc(c, s * 0.3, 0.6, TAU - 0.6, 16, Color(0.7, 0.5, 0.1, a), 3.0, true)
		_:
			ci.draw_rect(Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), Color(1, 0, 1, a))


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out
