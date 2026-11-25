#!/usr/bin/env python3
"""The market's trade goods: ten categories of fourteen goods (the game's
original fourteen among them). Writes scripts/trade_goods.gd (TradeGoods):
the new goods' item entries (merged into Items.ITEMS), the categories in
the market's order, who makes and who uses each good, and each new good's
icon (a shape and two colours - drawn by TradeGoods.draw_icon).

Edit the tables below and run:  python3 tools/trade_goods.py

Economies (Galaxy.ECONOMIES): mining, industrial, agricultural, hi_tech,
refinery, trade_hub, military, haven. A new good is made by every economy in
its category's MAKERS and used by two of its category's USERS (picked by the
good's name, so the same every run); Galaxy works out the rates from how many
stations of each kind the galaxy has (what's made outpaces what's used).
"""
import os, zlib

# [title, original goods in it, makers, users, new goods]
# a new good: (id, name, value (drachmas), shape, colour, colour 2, description)
CATEGORIES = [
    ["Food & drink", ["food", "water"], ["agricultural"],
     ["mining", "industrial", "military", "hi_tech", "haven", "trade_hub"], [
        ("grain", "Grain", 9, "sack", "e8c46a", "a07a32", "Wheat and barley from the hydroponic terraces - the bread of every station."),
        ("olive_oil", "Olive Oil", 26, "amphora", "9fae3c", "4d5a1c", "Pressed from the orbital groves. Food, lamp fuel and medicine in one jar."),
        ("wine", "Wine", 34, "amphora", "8c1f3a", "4a0d1d", "Dark as the wine-dark sea. Mixed with water, as civilised people drink it."),
        ("honey", "Honey", 30, "jar", "f0a830", "a8650f", "From bees kept in the agri-domes. Sweetener, preservative and wound salve."),
        ("figs", "Dried Figs", 16, "sack", "7b4a6e", "3e2236", "Sun-dried under grow-lamps. A sailor's ration on long hauls."),
        ("cheese", "Goat Cheese", 22, "box", "f2ead0", "b8a77a", "Brined in vats of seawater. Keeps for a voyage."),
        ("lentils", "Lentils", 8, "sack", "c9763a", "7a4220", "Cheap, filling and soldier's fare across New Hellas."),
        ("dried_fish", "Dried Fish", 14, "fish", "a8b8c4", "5a6a78", "Salted tuna from the sea-worlds' nets."),
        ("garum", "Garum", 28, "amphora", "b5652e", "5c2c12", "Fermented fish sauce. Foul to smell, prized at every table."),
        ("dates", "Dates", 18, "sack", "8a4a1c", "4a240c", "From the desert worlds' palms. Sweet and long-lasting."),
        ("saffron", "Saffron", 110, "vial", "e85a1a", "f2c230", "Crocus threads from the Theran gardens - worth its weight in silver."),
        ("barley_beer", "Barley Beer", 12, "jar", "d8a040", "8a5a1c", "Thick and cloudy. Barbarians drink it; so do miners."),
    ]],
    ["Medicine", ["medicine"], ["hi_tech"],
     ["military", "mining", "agricultural", "haven", "trade_hub"], [
        ("dittany", "Dittany of Crete", 48, "leaf", "7fbf5a", "c890d0", "The mountain herb that draws out arrowheads, as the deer of Ida knew."),
        ("antivenom", "Antivenom", 64, "vial", "5ad0a0", "1c6a50", "Brewed against the bites of the planets' serpents."),
        ("nanomeds", "Nanomeds", 120, "vial", "60d8ff", "1a5a9a", "Machines smaller than dust that knit flesh from within."),
        ("stim_packs", "Stim Packs", 42, "box", "ff6a5a", "8a2018", "Adrenaline and painkillers in one shot. Standard issue in every fleet."),
        ("cryo_plasma", "Cryo Plasma", 85, "canister", "a8e0ff", "3a7aa8", "Frozen blood plasma for the wounded of the border wars."),
        ("gene_serum", "Gene Serum", 160, "vial", "c070ff", "5a1a90", "Rewrites a sickness out of the body. The Asklepieia guard the recipe."),
        ("vaccines", "Vaccines", 55, "vial", "f0f0f0", "6aa0d0", "Against the plagues that travel with the trade fleets."),
        ("bandage_foam", "Bandage Foam", 24, "canister", "f0e0c0", "a08860", "Sprayed on a wound, it seals and hardens in a breath."),
        ("bone_knitters", "Bone Knitters", 95, "box", "e8e8d8", "8a8a70", "Splints that set a fracture in a day."),
        ("sedatives", "Sedatives", 36, "vial", "8090e0", "303a80", "Sleep in a phial - poppy refined in the labs."),
        ("oxygen_candles", "Oxygen Candles", 30, "canister", "60b0ff", "24507a", "Burn one in a holed hull and breathe."),
        ("med_scanners", "Med Scanners", 140, "chip", "5ae0c0", "1a5a4a", "Hand-held healers' eyes that see through skin."),
        ("asklepian_salve", "Asklepian Salve", 70, "jar", "e0c070", "7a5a1a", "The god of healing's own balm, made by his priests on Kos."),
    ]],
    ["Machinery", ["machinery"], ["industrial"],
     ["mining", "agricultural", "refinery", "military"], [
        ("drill_heads", "Drill Heads", 62, "blade", "c0c8d0", "606a74", "Diamond-tipped bits for the asteroid miners."),
        ("pumps", "Pumps", 48, "coil", "6a90b0", "2a4a60", "Move water, fuel and air through a station's veins."),
        ("reactor_coils", "Reactor Coils", 135, "coil", "ffb040", "8a4a10", "The windings at a reactor's heart. Handle with gloves."),
        ("hull_plates", "Hull Plates", 58, "ingot", "8a96a4", "3a4450", "Armoured plating for ships and stations."),
        ("girders", "Girders", 30, "ingot", "a0784a", "5a3a1a", "Bronze-steel beams that hold a station together."),
        ("bearings", "Gears and Bearings", 40, "coil", "d0b070", "7a5a20", "Toothed wheels as fine as the Antikythera engine's."),
        ("servos", "Servos", 76, "box", "70a0c0", "2a4a60", "The muscles of every automaton and robot arm."),
        ("pistons", "Hydraulic Pistons", 54, "canister", "b0b8c0", "50585e", "Lift a shuttle or crush a rock."),
        ("welding_rigs", "Welding Rigs", 88, "box", "ff8a30", "6a3010", "Plasma torches for the shipyards' crews."),
        ("rivets", "Rivets", 10, "box", "a0a0a8", "50505a", "Crates of them. Every hull needs ten thousand."),
        ("cables", "Power Cables", 22, "coil", "303a44", "e0a020", "Insulated cable by the spool."),
        ("airlocks", "Airlock Kits", 150, "box", "c8d0d8", "4a6070", "Doors between air and void, ready to fit."),
        ("water_mills", "Water Mills", 66, "coil", "6aa0c8", "2a5070", "Turbines for the agri-stations' irrigation rings."),
    ]],
    ["Technology", ["electronics"], ["hi_tech"],
     ["industrial", "military", "trade_hub", "refinery", "mining"], [
        ("processors", "Processors", 90, "chip", "40d0a0", "105a40", "Thinking stones, etched in the clean rooms of Ionia."),
        ("sensor_arrays", "Sensor Arrays", 125, "chip", "60c0ff", "1a4a7a", "Eyes that see a ship across a system."),
        ("holo_projectors", "Holo Projectors", 105, "orb", "70e0ff", "2a6a9a", "Throw light into shapes - maps, faces, gods."),
        ("data_crystals", "Data Crystals", 60, "crystal", "a0f0ff", "3a8aa8", "A library in a shard of quartz."),
        ("nav_computers", "Nav Computers", 170, "chip", "f0c040", "6a5010", "Plot a course through the gates as a pilot would."),
        ("comm_relays", "Comm Relays", 80, "coil", "80d0ff", "205a8a", "Carry a voice from one star to the next."),
        ("quantum_cores", "Quantum Cores", 320, "orb", "d080ff", "4a1a8a", "Hold a thought in two places at once. Rare and costly."),
        ("optic_fibre", "Optic Fibre", 34, "coil", "e0f0ff", "6a8aa8", "Light-threads by the spool."),
        ("automaton_brains", "Automaton Brains", 260, "chip", "ffd060", "7a5a10", "The minds of servants like you - made in Ephestos's image."),
        ("signal_boosters", "Signal Boosters", 56, "chip", "60ff90", "1a6a30", "Make a weak beacon heard."),
        ("circuit_boards", "Circuit Boards", 44, "chip", "3aa060", "e0c060", "The everyday stuff of every machine."),
        ("tutor_cores", "Tutor Cores", 115, "crystal", "ffe090", "8a6a20", "Teaching machines: rhetoric, geometry and the lyre."),
        ("antikythera_engines", "Star Reckoners", 210, "coil", "c89a4a", "5a3a10", "Bronze geared engines that compute the heavens, after the old wreck's design."),
    ]],
    ["Energy", ["fuel", "energy_cell"], ["refinery"],
     ["industrial", "military", "mining", "haven", "hi_tech"], [
        ("deuterium", "Deuterium", 38, "canister", "5ab0ff", "1a4a8a", "Heavy water's hydrogen - fusion fuel."),
        ("plasma_canisters", "Plasma Canisters", 72, "canister", "ff70d0", "7a1a6a", "Star-hot gas in a magnetic bottle."),
        ("antimatter_pods", "Antimatter Pods", 380, "orb", "ffffff", "8a40ff", "A spoonful could light a city - or end it."),
        ("fusion_pellets", "Fusion Pellets", 52, "box", "ffd040", "8a6a10", "Tiny suns, packed by the thousand."),
        ("reactor_rods", "Reactor Rods", 110, "canister", "70ff70", "1a6a1a", "Glowing fuel for the old fission stacks."),
        ("greek_fire", "Greek Fire", 140, "amphora", "ff6020", "6a1a0a", "The secret flame that burns on water - and in vacuum. Sold by licence only."),
        ("coolant", "Coolant", 18, "canister", "60f0ff", "1a6a7a", "Keeps reactors and plasma guns from melting."),
        ("lamp_oil", "Lamp Oil", 7, "amphora", "e8d080", "8a7030", "For the shrines' lamps, which must never go out."),
        ("star_resin", "Star Resin", 64, "jar", "ffb060", "8a4a10", "Sap of the giant ferns of the jungle worlds; burns hot and slow."),
        ("ion_gel", "Ion Gel", 46, "jar", "80a0ff", "2a3a9a", "Charge for the ion drives of small craft."),
        ("capacitors", "Capacitor Banks", 84, "box", "f0f040", "6a6a10", "Store a lightning bolt and loose it when you will."),
        ("solar_sails", "Solar Sails", 96, "bale", "f0f0ff", "8a90b0", "Folded mirror-cloth that sails on starlight."),
    ]],
    ["Minerals", ["iron_ore", "titanium_ore", "platinum_ore"], ["mining"],
     ["industrial", "refinery", "hi_tech"], [
        ("copper_ore", "Copper Ore", 18, "crystal", "d0703a", "6a3010", "From the green-veined rocks. Half of bronze."),
        ("tin_ore", "Tin Ore", 24, "crystal", "c0c8c8", "6a7070", "The other half - rarer, and fought over since the Bronze Age."),
        ("bronze_ingots", "Bronze Ingots", 46, "ingot", "c8903a", "6a4410", "Oxhide-shaped, as the old traders cast them."),
        ("silver_ore", "Silver Ore", 70, "crystal", "e0e8f0", "7a8a9a", "From mines like Laurion's. Owls are struck from it."),
        ("gold_ore", "Gold Ore", 150, "crystal", "ffd040", "8a6a10", "For masks, crowns and the treasuries of the gods."),
        ("orichalcum", "Orichalcum", 240, "ingot", "ff9a50", "8a3a10", "The red-gold metal of drowned Atlantis, found again in the deep fields."),
        ("cobalt", "Cobalt", 58, "crystal", "3a5aff", "10206a", "Blue ore for magnets and glazes."),
        ("obsidian", "Obsidian", 26, "crystal", "303040", "8a80a0", "Volcanic glass from Melos. Sharper than any steel."),
        ("marble", "Marble Blocks", 20, "box", "f4f0e8", "a8a090", "Parian white, for temples and statues."),
        ("salt", "Salt", 6, "sack", "f8f8f8", "a0a8b0", "From the evaporation pans. Wages were once paid in it."),
        ("sulphur", "Sulphur", 14, "crystal", "f0e040", "8a7a10", "From the volcanic moons - for fire, medicine and fumigation."),
    ]],
    ["Luxuries", ["luxury_goods"], ["trade_hub", "haven"],
     ["hi_tech", "military", "agricultural", "mining"], [
        ("silk", "Silk", 120, "bale", "f0d0e0", "a06080", "From the far east beyond the Ugarit gate. Light as air."),
        ("tyrian_purple", "Tyrian Purple", 280, "jar", "8a1a6a", "3a0a2a", "Dye from ten thousand sea-snails - the colour of kings."),
        ("perfume", "Perfume", 90, "vial", "ff90c0", "8a3a60", "Rose and myrrh in an alabaster flask."),
        ("amber", "Amber", 75, "gem", "ffa020", "8a4a0a", "Sun-stone from the cold north, with old insects asleep inside."),
        ("pearls", "Pearls", 160, "gem", "f8f0f0", "b0a8b0", "From the oyster beds of the sea-worlds."),
        ("red_figure_vases", "Red-Figure Vases", 130, "amphora", "d0703a", "1a1010", "Heroes painted in red on black. Collectors fight over them."),
        ("jewellery", "Jewellery", 210, "gem", "ffd040", "40d0ff", "Gold and gems worked by the Ionian smiths."),
        ("glassware", "Glassware", 55, "vial", "a0f0e0", "3a8a7a", "Blown glass, clear as water."),
        ("incense", "Incense", 45, "box", "c0a080", "6a4a30", "Frankincense and myrrh for the altars."),
        ("carpets", "Carpets", 100, "bale", "c03a3a", "e0b040", "Knotted with gryphons and lotus flowers."),
        ("statuettes", "Bronze Statuettes", 140, "statue", "c8903a", "5a3a10", "Gods and athletes, a hand high."),
        ("lyres", "Lyres", 85, "lyre", "c8903a", "f0e0c0", "Tortoiseshell and gut - Apollo's instrument."),
        ("papyrus", "Papyrus", 38, "scroll", "f0e0b0", "8a7a50", "Writing reed-paper from the river worlds."),
    ]],
    ["Arms", ["weapons"], ["military", "industrial"],
     ["haven", "mining", "trade_hub", "agricultural"], [
        ("rifle_charges", "Rifle Charges", 34, "box", "ff5040", "6a1a10", "Power packs for the automatons' rifles."),
        ("armour_plates", "Armour Plates", 92, "shield", "a0a8b0", "c8903a", "Body armour for marines - the linothorax made modern."),
        ("shield_emitters", "Shield Emitters", 180, "orb", "60c0ff", "1a4a8a", "Throw a field round a ship or a gate."),
        ("missile_crates", "Missile Crates", 150, "box", "6a7a50", "ffd040", "Warheads by the dozen - for warships, not for you."),
        ("space_mines", "Space Mines", 120, "orb", "ff3030", "3a3a3a", "Laid in the gate approaches when war comes."),
        ("grenades", "Grenades", 40, "orb", "50603a", "c0c040", "Pin and lever, as they've always been."),
        ("bronze_shields", "Bronze Shields", 70, "shield", "c8903a", "8a1a1a", "Ceremonial hoplons for parades and temples."),
        ("targeting_scopes", "Targeting Scopes", 95, "chip", "ff4040", "4a0a0a", "Find a target across the void."),
        ("drone_wings", "Drone Wings", 200, "blade", "8090a0", "ff5030", "Fighter drones, folded flat for shipping."),
        ("plasma_lances", "Plasma Lances", 165, "blade", "ff70d0", "6a1a6a", "A hoplite's spear with a sun at its tip."),
        ("ammunition", "Ammunition", 26, "box", "c0a040", "5a4a10", "Slugs and shells by the crate."),
        ("war_banners", "War Banners", 30, "bale", "c02020", "ffd040", "Standards to march under."),
        ("sling_bullets", "Sling Bullets", 8, "box", "808890", "404448", "Lead glands, stamped 'take this'. Cheap and still deadly."),
    ]],
    ["Wares & salvage", ["scrap"], ["agricultural", "industrial"],
     ["trade_hub", "mining", "military", "haven", "hi_tech"], [
        ("linen", "Linen", 28, "bale", "f0ecd8", "a8a080", "Woven flax for chitons and sails."),
        ("wool", "Wool", 20, "bale", "f0f0e8", "b0b0a0", "From the agri-domes' sheep."),
        ("leather", "Leather", 32, "bale", "8a5a2a", "4a2a0a", "Tanned hides for boots, belts and saddles."),
        ("rope", "Rope", 12, "coil", "c8a870", "7a5a2a", "Hemp and fibre cable. Every dock needs miles of it."),
        ("sailcloth", "Sailcloth", 36, "bale", "f8f4e0", "8a7a5a", "Heavy canvas for the sail-barges of the gas giants."),
        ("pottery", "Pottery", 16, "amphora", "c87040", "6a3418", "Pots, jugs and lamps for everyday use."),
        ("timber", "Timber", 22, "ingot", "a0703a", "5a3a1a", "Cedar and pine from the forest worlds."),
        ("glass", "Glass", 18, "crystal", "c0f0ff", "6aa0b0", "Panes and bottles."),
        ("soap", "Soap", 10, "box", "f0f8f0", "80a080", "Olive-oil soap. Even marines wash."),
        ("tools", "Tools", 38, "blade", "a0a8b0", "8a5a2a", "Hammers, adzes and saws."),
        ("furniture", "Furniture", 60, "box", "a0703a", "5a3a1a", "Couches, tables and chests, flat-packed."),
        ("clothing", "Clothing", 42, "bale", "4a6ac0", "f0f0f0", "Chitons, cloaks and flight suits."),
        ("scrap_electronics", "Scrap Electronics", 24, "chip", "6a7a6a", "3a4a3a", "Pulled from wrecks. Somebody can mend them."),
    ]],
    ["Exotics", ["alien_alloy"], ["hi_tech", "haven"],
     ["trade_hub", "industrial", "military"], [
        ("xeno_spores", "Xeno Spores", 130, "jar", "a0ff60", "3a7a1a", "Glowing spores from the fungal worlds. Keep the lid on."),
        ("void_crystals", "Void Crystals", 300, "crystal", "8040ff", "1a0a4a", "Grown in the dark between stars; they hum."),
        ("relic_shards", "Relic Shards", 220, "crystal", "e0c080", "6a5020", "Fragments of the builders' gates."),
        ("star_maps", "Star Maps", 180, "scroll", "203a6a", "ffe080", "Charts of routes no one flies any more."),
        ("linear_tablets", "Linear B Tablets", 160, "tablet", "c89060", "5a3a1a", "Clay tablets from the old palaces - inventories of oil and chariots."),
        ("hydra_scales", "Hydra Scales", 260, "scale", "4a9a5a", "1a4a2a", "Shed by the beast of Lerna. They grow back."),
        ("cyclops_lenses", "Cyclops Lenses", 240, "orb", "ffd040", "8a1a1a", "The great single eyes of the Cyclops engines."),
        ("kraken_ink", "Kraken Ink", 140, "jar", "201a30", "6040a0", "Black as night. Writes on anything, forever."),
        ("harpy_feathers", "Harpy Feathers", 110, "leaf", "8a6a4a", "e0c080", "Bronze-edged and razor-sharp."),
        ("titan_bones", "Titan Bones", 350, "statue", "e8e0c8", "8a8070", "From the old wars of the gods - so the sellers say."),
        ("ambrosia", "Ambrosia", 400, "jar", "ffe0a0", "ffa040", "The food of the gods. One taste and you'll swear it's real."),
        ("chimera_embers", "Chimera Embers", 190, "orb", "ff5020", "ffd040", "Coals from the lion-goat's fire. Still warm."),
        ("siren_shells", "Siren Shells", 150, "gem", "f0b0d0", "6a4a8a", "Hold one to your ear and hear singing."),
    ]],
]

ECONOMIES = ["mining", "industrial", "agricultural", "hi_tech", "refinery", "trade_hub", "military", "haven"]


def gd_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    ids = set()
    goods, cats, makes, uses = [], [], {e: [] for e in ECONOMIES}, {e: [] for e in ECONOMIES}
    for title, base, makers, users, new in CATEGORIES:
        assert len(base) + len(new) == 14, title
        for m in makers + users:
            assert m in ECONOMIES, m
        cats.append((title, base + [g[0] for g in new]))
        for g in new:
            gid = g[0]
            assert gid not in ids, gid
            ids.add(gid)
            goods.append((title, g))
            for m in makers:
                makes[m].append(gid)
            # two users, picked by the good's name (stable)
            h = zlib.crc32(gid.encode())
            picks = [users[h % len(users)], users[(h // 7 + 1 + h % (len(users) - 1)) % len(users)]]
            for u in dict.fromkeys(picks):
                if u not in makers:
                    uses[u].append(gid)
    assert len(ids) == 126, len(ids)

    out = []
    out.append("class_name TradeGoods")
    out.append("## The market's trade goods beyond the original fourteen: 126 of them, in")
    out.append("## ten categories of fourteen. GENERATED by tools/trade_goods.py - edit the")
    out.append("## tables there and run it again.")
    out.append("##")
    out.append("## GOODS: item entries (merged into Items.ITEMS: name, kind \"cargo\", value,")
    out.append("## desc, cat) plus each one's icon (shape, c1, c2 - draw_icon). CATEGORIES: the")
    out.append("## market's tabs in order, [title, [ids]] - the originals first in each. MAKES /")
    out.append("## USES: economy -> the new goods its stations make / use (Galaxy sets the rates).")
    out.append("")
    out.append("const GOODS := {")
    for title, (gid, name, value, shape, c1, c2, desc) in goods:
        out.append('\t%s: {"name": %s, "kind": "cargo", "value": %d, "cat": %s, "shape": %s, "c1": Color("%s"), "c2": Color("%s"),' % (
            gd_str(gid), gd_str(name), value, gd_str(title), gd_str(shape), c1, c2))
        out.append('\t\t"desc": %s},' % gd_str(desc))
    out.append("}")
    out.append("")
    out.append("const CATEGORIES := [")
    for title, members in cats:
        out.append("\t[%s, [%s]]," % (gd_str(title), ", ".join(gd_str(m) for m in members)))
    out.append("]")
    out.append("")
    for name, table in (("MAKES", makes), ("USES", uses)):
        out.append("const %s := {" % name)
        for e in ECONOMIES:
            out.append("\t%s: [%s]," % (gd_str(e), ", ".join(gd_str(g) for g in table[e])))
        out.append("}")
        out.append("")
    out.append(DRAW)
    path = os.path.join(os.path.dirname(__file__), "..", "scripts", "trade_goods.gd")
    open(path, "w").write("\n".join(out))
    print("wrote scripts/trade_goods.gd: %d goods, %d categories" % (len(goods), len(cats)))
    for e in ECONOMIES:
        print("  %-12s makes %2d  uses %2d" % (e, len(makes[e]), len(uses[e])))


DRAW = '''
## Draws a new good's icon in `rect`: its shape in its two colours.
static func draw_icon(ci: CanvasItem, id: String, rect: Rect2, dim := false) -> void:
	var g: Dictionary = GOODS[id]
	var a := 0.35 if dim else 1.0
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) / 2.0
	var c1 := Color(g["c1"], a)
	var c2 := Color(g["c2"], a)
	var ink := Color(0.05, 0.05, 0.08, 0.7 * a)
	var hi := Color(1, 1, 1, 0.35 * a)
	var P := func(pts: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in pts:
			out.append(c + p * s)
		return out
	match str(g["shape"]):
		"amphora":
			var body: PackedVector2Array = P.call([Vector2(-0.22, -0.55), Vector2(0.22, -0.55), Vector2(0.2, -0.4), Vector2(0.48, -0.1),
				Vector2(0.45, 0.35), Vector2(0.12, 0.72), Vector2(-0.12, 0.72), Vector2(-0.45, 0.35), Vector2(-0.48, -0.1), Vector2(-0.2, -0.4)])
			ci.draw_colored_polygon(body, c1)
			ci.draw_polyline(body + PackedVector2Array([body[0]]), ink, 1.5, true)
			ci.draw_rect(Rect2(c + Vector2(-0.26, -0.72) * s, Vector2(0.52, 0.18) * s), c2)
			ci.draw_arc(c + Vector2(-0.4, -0.3) * s, s * 0.16, PI * 0.5, PI * 1.5, 10, c2, 2.0, true)
			ci.draw_arc(c + Vector2(0.4, -0.3) * s, s * 0.16, -PI * 0.5, PI * 0.5, 10, c2, 2.0, true)
			ci.draw_line(c + Vector2(-0.44, 0.1) * s, c + Vector2(0.44, 0.1) * s, c2, s * 0.1)
		"jar":
			var body: PackedVector2Array = P.call([Vector2(-0.4, -0.38), Vector2(0.4, -0.38), Vector2(0.48, 0.0), Vector2(0.42, 0.6), Vector2(-0.42, 0.6), Vector2(-0.48, 0.0)])
			ci.draw_colored_polygon(body, c1)
			ci.draw_polyline(body + PackedVector2Array([body[0]]), ink, 1.5, true)
			ci.draw_rect(Rect2(c + Vector2(-0.44, -0.62) * s, Vector2(0.88, 0.24) * s), c2)
			ci.draw_line(c + Vector2(-0.3, -0.1) * s, c + Vector2(-0.3, 0.4) * s, hi, s * 0.1)
		"sack":
			var body: PackedVector2Array = P.call([Vector2(-0.2, -0.5), Vector2(0.2, -0.5), Vector2(0.5, 0.1), Vector2(0.45, 0.62), Vector2(-0.45, 0.62), Vector2(-0.5, 0.1)])
			ci.draw_colored_polygon(body, c1)
			ci.draw_polyline(body + PackedVector2Array([body[0]]), ink, 1.5, true)
			ci.draw_line(c + Vector2(-0.24, -0.45) * s, c + Vector2(0.24, -0.45) * s, c2, s * 0.12)
			ci.draw_colored_polygon(P.call([Vector2(-0.12, -0.5), Vector2(0.0, -0.75), Vector2(0.12, -0.5)]), c1)
			for i in 5:
				ci.draw_circle(c + Vector2(-0.25 + 0.12 * i, 0.25 + 0.06 * (i % 2)) * s, s * 0.06, c2)
		"box":
			var top: PackedVector2Array = P.call([Vector2(-0.6, -0.25), Vector2(0.0, -0.55), Vector2(0.6, -0.25), Vector2(0.0, 0.05)])
			var left: PackedVector2Array = P.call([Vector2(-0.6, -0.25), Vector2(0.0, 0.05), Vector2(0.0, 0.7), Vector2(-0.6, 0.4)])
			var right: PackedVector2Array = P.call([Vector2(0.0, 0.05), Vector2(0.6, -0.25), Vector2(0.6, 0.4), Vector2(0.0, 0.7)])
			ci.draw_colored_polygon(left, c1.darkened(0.25))
			ci.draw_colored_polygon(right, c1.darkened(0.45))
			ci.draw_colored_polygon(top, c1)
			ci.draw_line(c + Vector2(-0.3, -0.4) * s, c + Vector2(0.3, -0.1) * s, c2, s * 0.1)
			ci.draw_line(c + Vector2(-0.3, 0.2) * s, c + Vector2(-0.3, 0.55) * s, c2, s * 0.08)
			for poly in [top, left, right]:
				ci.draw_polyline(poly + PackedVector2Array([poly[0]]), ink, 1.2, true)
		"ingot":
			for k in 2:
				var o := Vector2(0, 0.3 - 0.4 * k)
				var face: PackedVector2Array = P.call([Vector2(-0.6, 0.0) + o, Vector2(-0.4, -0.22) + o, Vector2(0.6, -0.22) + o, Vector2(0.4, 0.0) + o])
				var side: PackedVector2Array = P.call([Vector2(-0.6, 0.0) + o, Vector2(0.4, 0.0) + o, Vector2(0.4, 0.22) + o, Vector2(-0.6, 0.22) + o])
				ci.draw_colored_polygon(side, c1.darkened(0.35))
				ci.draw_colored_polygon(face, c1.lightened(0.1))
				ci.draw_polyline(side + PackedVector2Array([side[0]]), ink, 1.2, true)
				ci.draw_line(c + (Vector2(-0.35, -0.12) + o) * s, c + (Vector2(0.4, -0.12) + o) * s, c2, 1.5)
		"vial":
			ci.draw_rect(Rect2(c + Vector2(-0.12, -0.75) * s, Vector2(0.24, 0.16) * s), c2)
			ci.draw_rect(Rect2(c + Vector2(-0.08, -0.6) * s, Vector2(0.16, 0.3) * s), Color(0.85, 0.9, 1.0, 0.6 * a))
			ci.draw_circle(c + Vector2(0, 0.25) * s, s * 0.45, Color(0.85, 0.9, 1.0, 0.45 * a))
			ci.draw_circle(c + Vector2(0, 0.32) * s, s * 0.36, c1)
			ci.draw_arc(c + Vector2(0, 0.25) * s, s * 0.45, 0, TAU, 24, ink, 1.5, true)
			ci.draw_circle(c + Vector2(-0.15, 0.12) * s, s * 0.08, hi)
		"canister":
			ci.draw_rect(Rect2(c + Vector2(-0.32, -0.55) * s, Vector2(0.64, 1.2) * s), c1)
			ci.draw_rect(Rect2(c + Vector2(-0.32, -0.55) * s, Vector2(0.64, 1.2) * s), ink, false, 1.5)
			ci.draw_rect(Rect2(c + Vector2(-0.36, -0.2) * s, Vector2(0.72, 0.14) * s), c2)
			ci.draw_rect(Rect2(c + Vector2(-0.36, 0.3) * s, Vector2(0.72, 0.14) * s), c2)
			ci.draw_rect(Rect2(c + Vector2(-0.14, -0.72) * s, Vector2(0.28, 0.17) * s), c2)
			ci.draw_line(c + Vector2(-0.2, -0.45) * s, c + Vector2(-0.2, 0.55) * s, hi, s * 0.08)
		"chip":
			ci.draw_rect(Rect2(c + Vector2(-0.5, -0.5) * s, Vector2(1.0, 1.0) * s), c2)
			for i in 4:
				var t := -0.36 + 0.24 * i
				for side in [-1.0, 1.0]:
					ci.draw_line(c + Vector2(t, 0.5 * side) * s, c + Vector2(t, 0.68 * side) * s, Color(0.85, 0.85, 0.7, a), 2.0)
					ci.draw_line(c + Vector2(0.5 * side, t) * s, c + Vector2(0.68 * side, t) * s, Color(0.85, 0.85, 0.7, a), 2.0)
			ci.draw_rect(Rect2(c + Vector2(-0.28, -0.28) * s, Vector2(0.56, 0.56) * s), c1)
			ci.draw_rect(Rect2(c + Vector2(-0.5, -0.5) * s, Vector2(1.0, 1.0) * s), ink, false, 1.2)
		"crystal":
			var shard: PackedVector2Array = P.call([Vector2(0.0, -0.75), Vector2(0.32, -0.2), Vector2(0.22, 0.6), Vector2(-0.22, 0.6), Vector2(-0.32, -0.2)])
			ci.draw_colored_polygon(shard, c1)
			ci.draw_colored_polygon(P.call([Vector2(0.0, -0.75), Vector2(0.32, -0.2), Vector2(0.22, 0.6), Vector2(0.0, 0.2)]), c1.darkened(0.25))
			ci.draw_colored_polygon(P.call([Vector2(-0.55, 0.0), Vector2(-0.3, 0.1), Vector2(-0.35, 0.62), Vector2(-0.6, 0.62)]), c2)
			ci.draw_polyline(shard + PackedVector2Array([shard[0]]), ink, 1.3, true)
			ci.draw_line(c + Vector2(-0.12, -0.35) * s, c + Vector2(-0.18, 0.3) * s, hi, 2.0)
		"orb":
			ci.draw_circle(c, s * 0.62, Color(c2, 0.5 * a))
			ci.draw_circle(c, s * 0.5, c1)
			ci.draw_arc(c, s * 0.62, 0, TAU, 28, c2, 2.0, true)
			ci.draw_arc(c, s * 0.5, -0.4, 1.4, 12, ink, 1.5, true)
			ci.draw_circle(c + Vector2(-0.18, -0.18) * s, s * 0.14, hi)
		"bale":
			ci.draw_colored_polygon(P.call([Vector2(-0.6, -0.2), Vector2(0.6, -0.2), Vector2(0.6, 0.5), Vector2(-0.6, 0.5)]), c1)
			ci.draw_circle(c + Vector2(-0.6, 0.15) * s, s * 0.35, c1.darkened(0.15))
			ci.draw_arc(c + Vector2(-0.6, 0.15) * s, s * 0.22, 0, TAU, 16, c2, 2.0, true)
			ci.draw_arc(c + Vector2(-0.6, 0.15) * s, s * 0.1, 0, TAU, 12, c2, 1.5, true)
			ci.draw_line(c + Vector2(-0.1, -0.2) * s, c + Vector2(-0.1, 0.5) * s, c2, s * 0.1)
			ci.draw_line(c + Vector2(0.3, -0.2) * s, c + Vector2(0.3, 0.5) * s, c2, s * 0.1)
			ci.draw_rect(Rect2(c + Vector2(-0.6, -0.2) * s, Vector2(1.2, 0.7) * s), ink, false, 1.2)
		"coil":
			ci.draw_circle(c, s * 0.62, c1)
			ci.draw_circle(c, s * 0.24, c2)
			for k in 3:
				ci.draw_arc(c, s * (0.32 + 0.1 * k), 0, TAU, 24, c1.darkened(0.3), 1.5, true)
			ci.draw_arc(c, s * 0.62, 0, TAU, 28, ink, 1.5, true)
			ci.draw_line(c + Vector2(0.5, 0.35) * s, c + Vector2(0.8, 0.7) * s, c1.darkened(0.2), s * 0.12)
		"leaf":
			ci.draw_line(c + Vector2(0.0, 0.75) * s, c + Vector2(0.0, -0.6) * s, c1.darkened(0.35), 2.0)
			for k in 3:
				var y := 0.35 - 0.38 * k
				for side in [-1.0, 1.0]:
					ci.draw_colored_polygon(P.call([Vector2(0, y), Vector2(0.28 * side, y - 0.32), Vector2(0.5 * side, y - 0.15), Vector2(0.22 * side, y + 0.06)]), c1)
			ci.draw_circle(c + Vector2(0, -0.66) * s, s * 0.14, c2)
		"fish":
			ci.draw_colored_polygon(P.call([Vector2(-0.6, 0.0), Vector2(-0.1, -0.32), Vector2(0.35, -0.2), Vector2(0.55, 0.0), Vector2(0.35, 0.2), Vector2(-0.1, 0.32)]), c1)
			ci.draw_colored_polygon(P.call([Vector2(0.5, 0.0), Vector2(0.78, -0.3), Vector2(0.78, 0.3)]), c2)
			ci.draw_circle(c + Vector2(-0.35, -0.06) * s, s * 0.06, ink)
			ci.draw_line(c + Vector2(-0.05, -0.25) * s, c + Vector2(-0.05, 0.25) * s, c2, 1.5)
		"blade":
			ci.draw_colored_polygon(P.call([Vector2(-0.08, -0.78), Vector2(0.1, -0.6), Vector2(0.1, 0.25), Vector2(-0.08, 0.25)]), c1)
			ci.draw_line(c + Vector2(0.0, -0.7) * s, c + Vector2(0.0, 0.2) * s, hi, 1.5)
			ci.draw_rect(Rect2(c + Vector2(-0.3, 0.25) * s, Vector2(0.6, 0.1) * s), c2)
			ci.draw_rect(Rect2(c + Vector2(-0.07, 0.35) * s, Vector2(0.14, 0.38) * s), c2.darkened(0.3))
		"gem":
			var gem: PackedVector2Array = P.call([Vector2(-0.5, -0.2), Vector2(-0.25, -0.5), Vector2(0.25, -0.5), Vector2(0.5, -0.2), Vector2(0.0, 0.6)])
			ci.draw_colored_polygon(gem, c1)
			ci.draw_colored_polygon(P.call([Vector2(-0.5, -0.2), Vector2(0.5, -0.2), Vector2(0.0, 0.6)]), c1.darkened(0.2))
			ci.draw_colored_polygon(P.call([Vector2(-0.25, -0.5), Vector2(0.25, -0.5), Vector2(0.12, -0.2), Vector2(-0.12, -0.2)]), c1.lightened(0.3))
			ci.draw_polyline(gem + PackedVector2Array([gem[0]]), ink, 1.3, true)
			ci.draw_circle(c + Vector2(0.45, 0.45) * s, s * 0.14, c2)
		"scroll":
			ci.draw_rect(Rect2(c + Vector2(-0.5, -0.4) * s, Vector2(1.0, 0.8) * s), c1)
			ci.draw_circle(c + Vector2(-0.5, 0.0) * s, s * 0.12, c1.darkened(0.3))
			ci.draw_rect(Rect2(c + Vector2(-0.62, -0.5) * s, Vector2(0.12, 1.0) * s), c1.darkened(0.3))
			ci.draw_rect(Rect2(c + Vector2(0.5, -0.5) * s, Vector2(0.12, 1.0) * s), c1.darkened(0.3))
			for k in 4:
				ci.draw_line(c + Vector2(-0.35, -0.25 + 0.16 * k) * s, c + Vector2(0.35, -0.25 + 0.16 * k) * s, c2, 1.5)
		"tablet":
			ci.draw_colored_polygon(P.call([Vector2(-0.45, -0.6), Vector2(0.45, -0.55), Vector2(0.5, 0.6), Vector2(-0.48, 0.62)]), c1)
			for k in 5:
				var y := -0.42 + 0.2 * k
				for j in 4:
					ci.draw_line(c + Vector2(-0.32 + 0.18 * j, y) * s, c + Vector2(-0.24 + 0.18 * j, y + 0.08) * s, c2, 1.5)
		"scale":
			for k in 3:
				for j in 3 - (k % 2):
					var p := c + Vector2(-0.38 + 0.38 * j + 0.19 * (k % 2), -0.35 + 0.35 * k) * s
					ci.draw_circle(p, s * 0.24, c1 if (j + k) % 2 == 0 else c1.darkened(0.2))
					ci.draw_arc(p, s * 0.24, PI * 0.1, PI * 0.9, 10, c2, 2.0, true)
		"statue":
			ci.draw_rect(Rect2(c + Vector2(-0.4, 0.45) * s, Vector2(0.8, 0.22) * s), c2)
			ci.draw_colored_polygon(P.call([Vector2(-0.2, 0.45), Vector2(-0.15, -0.1), Vector2(-0.3, -0.25), Vector2(-0.1, -0.35),
				Vector2(0.1, -0.35), Vector2(0.3, -0.25), Vector2(0.15, -0.1), Vector2(0.2, 0.45)]), c1)
			ci.draw_circle(c + Vector2(0, -0.52) * s, s * 0.16, c1)
		"lyre":
			ci.draw_arc(c + Vector2(-0.25, -0.1) * s, s * 0.35, PI * 0.5, PI * 1.5, 12, c1, s * 0.12, true)
			ci.draw_arc(c + Vector2(0.25, -0.1) * s, s * 0.35, -PI * 0.5, PI * 0.5, 12, c1, s * 0.12, true)
			ci.draw_line(c + Vector2(-0.45, -0.45) * s, c + Vector2(0.45, -0.45) * s, c1, s * 0.1)
			ci.draw_circle(c + Vector2(0, 0.35) * s, s * 0.3, c1.darkened(0.2))
			for k in 4:
				ci.draw_line(c + Vector2(-0.15 + 0.1 * k, -0.45) * s, c + Vector2(-0.15 + 0.1 * k, 0.3) * s, c2, 1.0)
		"shield":
			ci.draw_circle(c, s * 0.66, c1)
			ci.draw_arc(c, s * 0.66, 0, TAU, 28, c2, s * 0.1, true)
			ci.draw_circle(c, s * 0.18, c2)
			ci.draw_arc(c, s * 0.66, 0, TAU, 28, ink, 1.2, true)
		_:
			ci.draw_rect(Rect2(c - Vector2(0.5, 0.5) * s, Vector2(1, 1) * s), c1)
'''

if __name__ == "__main__":
    main()
