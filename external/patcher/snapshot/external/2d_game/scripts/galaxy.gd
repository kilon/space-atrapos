extends Node
## Autoload "Galaxy": the sandbox simulation that runs behind the game.
##
## - 13 star systems linked by jump gates, owned by four star empires that
##   rebuilt the Greek civilisations in space (Athenian League, Spartan
##   Hegemony, Minoan Thalassocracy, Mycenaean Kingdoms) or by the Sea Peoples.
## - Every station has a market: stock per commodity, production and
##   consumption from its economy type, and prices that follow supply.
## - NPC traders (each with its own cargo and credits) buy cheap and sell dear
##   across stations and systems, moving goods and evening out prices.
##   Traders in the player's system are flown as real ships by the game;
##   elsewhere they're simulated abstractly.
## - Pirates hijack traders and steal their cargo.
## - Empires drift between peace and war; at war they raid and capture
##   border systems. The player has a reputation with each empire.
## The state is saved with the game (get_save_data / load_save_data).

signal news_posted(text: String, kind: String)
## A trader started a leg inside the current system (the game spawns a ship).
signal trader_appeared(record: Dictionary)
## Diplomacy or ownership changed (maps / HUD refresh).
signal politics_changed

const HOME := "atrapos"
## The empire that owns the starting cluster (Atrapos and its neighbours).
const HOME_EMPIRE := "minoa"
const TICK := 2.0                 # economy tick, seconds
## Units per second a production / consumption rate of 1 means. Low enough
## that the traders (and you) can carry what the stations need: most of what
## a station uses is shipped in, so hauling - not the rates - sets the prices.
const RATE := 0.1
const TRADER_SPEED := 150.0       # abstract travel speed, px/s
const GATE_JUMP_TIME := 6.0
## Trader planning: how much a shortage at the destination is worth, per unit
## (times the good's value, plus a flat part) on top of the trade margin.
const NEED_PREMIUM := 2.0
const NEED_FLAT := 25.0
## Empires at war use this much more weapons, fuel and medicine.
const WAR_DEMAND := 1.3
const TRADER_TARGET := 110        # galaxy-wide trader population (~2 a system)
const CARGO_CAPACITY := 60        # player's hold for trade goods (units)
## Your standing with each empire (and with the independents), -100..100:
## [name, from] - the tier is the last whose `from` you've reached. Hostile:
## their warships attack you and their stations refuse you. It moves with
## what you do (REP_*): missions, trade and bounties raise it; attacking
## their ships lowers it - slowly, a ship at a time - and a bad name fades
## back toward neutral over time (REP_RECOVER a minute).
const REP_TIERS := [["Hostile", -100.0], ["Unfriendly", -50.0], ["Neutral", -15.0], ["Cordial", 15.0],
	["Friendly", 40.0], ["Allied", 70.0]]
const HOSTILE_REP := -50.0
const REP_TRADE := 0.001          # per drachma you trade at one of their stations (times REP_GAIN: 10,000 dr, +1)
const REP_PROVOKE := -2.0         # firing on one of their ships (once a ship)
const REP_KILL := -8.0            # destroying one of their ships
const REP_LAWLESS := -2.0         # destroying a civilian in someone's space (its owner frowns)
const REP_RECOVER := 1.0          # a bad name fades this much a minute (toward 0)
## Market prices at a station by your standing with its owner: [buy, sell]
## multipliers (Unfriendly pays more and gets less; Allied the best deal).
const REP_PRICES := {"Hostile": [1.15, 0.85], "Unfriendly": [1.1, 0.9], "Neutral": [1.0, 1.0],
	"Cordial": [0.98, 1.01], "Friendly": [0.95, 1.03], "Allied": [0.9, 1.05]}
## Pirate bounties from the system's owner, by your standing with it.
const REP_BOUNTY := {"Friendly": 1.1, "Allied": 1.25}
## Your market footprint: each unit you buy at a station pushes its price up by
## PLAYER_IMPACT (a fraction, compounding), each unit you sell pushes it down -
## up to 1 + IMPACT_SCARCE times as hard on goods the station is short of
## (selling a full hold where it's needed soon floods the market). The push
## fades by IMPACT_DECAY per economy tick (half gone in about 1.5 minutes),
## so big hauls on one route pay less and spreading them out pays more.
const PLAYER_IMPACT := 0.003
const IMPACT_SCARCE := 1.0
const IMPACT_DECAY := 0.985
## Pirate bounties: credits per point of hull + shields, plus a flat part.
const BOUNTY_PER_POINT := 1.0
const BOUNTY_BASE := 60.0

## The great powers of the 31st century: star nations that rebuilt the old
## Greek civilisations among the stars (internal id "pirates" = the Sea Peoples).
const EMPIRES := {
	"athens": {"name": "Athenian League", "short": "Athenian", "color": Color(0.35, 0.8, 1.0),
		"desc": "A democratic federation of free colonies, heirs of Athens. Traders, scholars and the finest navy among the stars - their owl-crested fleets guard your home port."},
	"sparta": {"name": "Spartan Hegemony", "short": "Spartan", "color": Color(1.0, 0.5, 0.18),
		"desc": "A militarised star state where every citizen serves. Bronze-armoured warships, fortress stations, and a lambda on every hull. Few words, many guns."},
	"minoa": {"name": "Minoan Thalassocracy", "short": "Minoan", "color": Color(0.3, 1.0, 0.75),
		"desc": "The oldest of the star nations: a maritime empire of research palaces and bull-horned ships, ruled from the orbital palace of Knossos. Rich in technology, short on food."},
	"mycenae": {"name": "Mycenaean Kingdoms", "short": "Mycenaean", "color": Color(1.0, 0.85, 0.3),
		"desc": "Warrior-kings of cyclopean citadels and golden fleets. Miners and shipwrights, allied by blood with Sparta, rivals of the Minoans."},
	"ionia": {"name": "Ionian League", "short": "Ionian", "color": Color(0.5, 0.58, 1.0),
		"desc": "Philosopher-republics of the eastern lanes - Miletos, Ephesos, Samos - heirs of the Ionian cities where science began. Lapis-and-gold fleets crowned with Ionic columns, floating garden isles and star-gazing observatories. Kin to the Athenians, wary of Sparta."},
	"cyclades": {"name": "Cycladic Isles", "short": "Cycladic", "color": Color(1.0, 0.62, 0.82),
		"desc": "The oldest seafarers of the Aegean, reborn among the stars: island-hopping traders, quarrymen and sculptors of white marble and black obsidian, their worlds set in a circle round a sacred centre. Calm, old and proud - friends of the Minoans, wary of the warlike mainland."},
	"independent": {"name": "Independents", "short": "Independent", "color": Color(0.8, 0.82, 0.86),
		"desc": "Free ports, waystations and the ships that answer to no empire. Neutral with everyone, they trade with every side and keep out of the empires' wars - only the Sea Peoples prey on them."},
	"pirates": {"name": "Sea Peoples", "short": "Sea People", "color": Color(1.0, 0.22, 0.22),
		"desc": "Raider clans from beyond the charted lanes - like the Sea Peoples who once toppled the Bronze Age. They hijack freighters and sell the loot in their dens."},
}
const MAJOR := ["athens", "sparta", "minoa", "mycenae", "ionia", "cyclades"]

## Trade goods (Items.ITEMS ids) and their base prices.
const BASE_COMMODITIES := ["food", "water", "medicine", "machinery", "electronics", "fuel", "luxury_goods", "weapons",
	"iron_ore", "titanium_ore", "platinum_ore", "energy_cell", "scrap", "alien_alloy"]
## Every trade good: the original fourteen (each station stocks them all) and
## TradeGoods' 126 (a station stocks those its economy makes or uses - see
## _plan_goods). A station deals in whatever is in its "stock".
var COMMODITIES: Array = BASE_COMMODITIES + TradeGoods.GOODS.keys()
## Goods dearer in wartime.
const WAR_GOODS := ["weapons", "fuel", "medicine"]
## TradeGoods' goods by economy: {economy: {"produce": {id: rate}, "consume":
## {id: rate}}} - rates worked out for this galaxy (_plan_goods).
var _econ_goods := {}

## Rates times RATE are units per second at full efficiency. Balanced so that, across
## the galaxy's stations, every good is made at least as fast as it's used
## when the chains run (tools: the economy report in external/patcher/pending.md).
const ECONOMIES := {
	"mining": {"name": "Mining colony", "produce": {"iron_ore": 3.6, "titanium_ore": 2.6, "platinum_ore": 1.2, "scrap": 0.8},
		"consume": {"food": 1.0, "water": 1.0, "machinery": 0.6, "medicine": 0.4, "fuel": 0.6}},
	"industrial": {"name": "Industrial yards", "produce": {"machinery": 3.0, "weapons": 0.6, "energy_cell": 0.8},
		"consume": {"iron_ore": 2.4, "titanium_ore": 1.0, "fuel": 1.0, "food": 0.7, "scrap": 0.6}},
	"agricultural": {"name": "Agri-station", "produce": {"food": 7.0, "water": 4.5},
		"consume": {"machinery": 0.6, "medicine": 0.5, "fuel": 0.6, "electronics": 0.2}},
	"hi_tech": {"name": "Research station", "produce": {"electronics": 1.3, "medicine": 1.1, "alien_alloy": 0.1},
		"consume": {"platinum_ore": 0.4, "titanium_ore": 0.5, "energy_cell": 0.7, "food": 0.5, "luxury_goods": 0.3}},
	"refinery": {"name": "Refinery", "produce": {"fuel": 4.5, "energy_cell": 2.0},
		"consume": {"iron_ore": 1.0, "water": 0.8, "machinery": 0.4, "food": 0.4}},
	"trade_hub": {"name": "Trade hub", "produce": {"luxury_goods": 0.9},
		"consume": {"food": 0.8, "water": 0.7, "electronics": 0.6, "medicine": 0.4, "fuel": 0.8, "luxury_goods": 0.3}},
	"military": {"name": "Military base", "produce": {"weapons": 0.9},
		"consume": {"fuel": 1.5, "food": 0.9, "machinery": 0.5, "medicine": 0.6, "weapons": 0.3}},
	"haven": {"name": "Pirate haven", "produce": {"luxury_goods": 0.4},
		"consume": {"food": 1.0, "weapons": 0.8, "fuel": 1.0, "medicine": 0.6}},
}

## Production chains: a station's output needs these inputs in stock;
## starved stations slow down (so traders keep the chains running).
const INPUTS := {"mining": ["food", "water"], "industrial": ["iron_ore", "titanium_ore"],
	"agricultural": ["machinery"], "hi_tech": ["platinum_ore", "energy_cell"], "refinery": ["iron_ore", "water"],
	"trade_hub": [], "military": ["fuel", "food"], "haven": ["food"]}

## System states (they come and go, with news): they change output, demand
## and danger. produce = output multiplier, demand = item -> consumption
## multiplier, pirates = extra pirate activity.
const STATES := {
	"none": {"name": "Stable", "desc": "Nothing unusual."},
	"boom": {"name": "Boom", "desc": "Trade is thriving: output up, luxuries in demand.", "produce": 1.5, "demand": {"luxury_goods": 2.0}},
	"bust": {"name": "Bust", "desc": "An economic slump: output down.", "produce": 0.55},
	"famine": {"name": "Famine", "desc": "Food shortage: food and water fetch premium prices.", "demand": {"food": 3.0, "water": 2.0}},
	"outbreak": {"name": "Outbreak", "desc": "A disease outbreak: medicine is desperately needed.", "demand": {"medicine": 3.5}},
	"civil_unrest": {"name": "Civil Unrest", "desc": "Riots and strikes: output down, weapons in demand.", "produce": 0.75, "demand": {"weapons": 2.2}},
	"pirate_raids": {"name": "Pirate Raids", "desc": "Sea Peoples raiders prowl the lanes: more pirates, bigger bounties.", "pirates": 0.4},
	"expansion": {"name": "Expansion", "desc": "New colonies are being built: machinery and electronics in demand.", "demand": {"machinery": 2.0, "electronics": 1.7}},
}

## Star types: their StarGen template (+ colours), size and map colour.
## Each system's sun is a different StarGen variant of its type's template.
const STARS := {
	"yellow": {"name": "Yellow dwarf", "template": "yellow_sun", "color": Color(1.0, 0.86, 0.5), "radius": 420.0},
	"orange": {"name": "Orange dwarf", "template": "yellow_sun", "color": Color(1.0, 0.62, 0.3), "radius": 380.0,
		"look": {"c_dark": Color(0.42, 0.1, 0.01), "c_mid": Color(1.0, 0.42, 0.05), "c_hot": Color(1.0, 0.76, 0.38), "c_corona": Color(1.0, 0.52, 0.16)}},
	"red": {"name": "Red giant", "template": "red_giant", "color": Color(1.0, 0.4, 0.28), "radius": 560.0},
	"white": {"name": "White star", "template": "white_star", "color": Color(0.92, 0.95, 1.0), "radius": 400.0},
	"blue": {"name": "Blue giant", "template": "white_star", "color": Color(0.55, 0.72, 1.0), "radius": 600.0,
		"look": {"c_dark": Color(0.2, 0.35, 0.8), "c_mid": Color(0.5, 0.68, 1.0), "c_hot": Color(0.9, 0.95, 1.0), "c_corona": Color(0.5, 0.7, 1.0)}},
	"brown": {"name": "Brown dwarf", "template": "brown_dwarf", "color": Color(0.75, 0.25, 0.12), "radius": 300.0},
	"pulsar": {"name": "Pulsar", "template": "pulsar", "color": Color(0.5, 0.75, 1.0), "radius": 150.0},
	"magnetar": {"name": "Magnetar", "template": "magnetar", "color": Color(0.65, 0.5, 1.0), "radius": 150.0},
}


## The sun of system `id`: its type's template, a variant unique to the
## system (the home system keeps the template itself).
static func star_spec(id: String) -> Dictionary:
	var t: Dictionary = STARS[SYSTEMS[id]["star"]]
	return StarGen.generate(t["template"], SYSTEMS.keys().find(id), t.get("look", {}))


## The galaxy: map position (for the galaxy map), owner, star and pirate
## activity. Planets, stations and fields are generated (except the home system, Knossos).
## Names: each system - and its star, which shares the name - is one of its
## empire's most famous cities or places; its planets are named after lesser
## ones (PLANET_NAMES). The ids are the old names (saves and quests use them).
## The hand-made heart of the galaxy (the story's systems); the rest is
## grown from it - see _grow() and SYSTEMS / LINKS below.
const BASE_SYSTEMS := {
	"atrapos": {"name": "Knossos", "pos": Vector2(430, 330), "owner": "minoa", "star": "yellow", "pirates": 0.45},
	"klotho": {"name": "Phaistos", "pos": Vector2(290, 240), "owner": "minoa", "star": "white", "pirates": 0.25},
	"lachesis": {"name": "Malia", "pos": Vector2(350, 470), "owner": "minoa", "star": "orange", "pirates": 0.4},
	"delos": {"name": "Zakros", "pos": Vector2(560, 220), "owner": "minoa", "star": "blue", "pirates": 0.3},
	"kyros": {"name": "Sparta", "pos": Vector2(710, 330), "owner": "sparta", "star": "yellow", "pirates": 0.15},
	"naxos": {"name": "Mykenai", "pos": Vector2(830, 190), "owner": "mycenae", "star": "orange", "pirates": 0.3},
	"thera": {"name": "Thermopylai", "pos": Vector2(790, 480), "owner": "sparta", "star": "red", "pirates": 0.4},
	"pylos": {"name": "Pylos", "pos": Vector2(620, 530), "owner": "mycenae", "star": "white", "pirates": 0.5},
	"nyx": {"name": "Athenai", "pos": Vector2(150, 370), "owner": "athens", "star": "blue", "pirates": 0.2},
	"erebos": {"name": "Marathon", "pos": Vector2(130, 190), "owner": "athens", "star": "magnetar", "pirates": 0.3},
	"hekate": {"name": "Piraeus", "pos": Vector2(200, 550), "owner": "athens", "star": "white", "pirates": 0.4},
	"tartaros": {"name": "Ugarit", "pos": Vector2(470, 620), "owner": "pirates", "star": "brown", "pirates": 1.0},
	"skylla": {"name": "Lukka", "pos": Vector2(940, 340), "owner": "pirates", "star": "pulsar", "pirates": 1.0},
	"miletos": {"name": "Miletos", "pos": Vector2(960, 560), "owner": "ionia", "star": "blue", "pirates": 0.2},
	"ephesos": {"name": "Ephesos", "pos": Vector2(1090, 430), "owner": "ionia", "star": "white", "pirates": 0.25},
	"samos": {"name": "Samos", "pos": Vector2(1080, 650), "owner": "ionia", "star": "yellow", "pirates": 0.35},
	"keros": {"name": "Keros", "pos": Vector2(800, 790), "owner": "cyclades", "star": "white", "pirates": 0.2},
}
## Planets' names: lesser cities and places of the system's empire, handed out
## in turn through its systems (36+ each: three systems of up to 12 planets; never a system's name; the home system's four
## planets are named in PlanetData: Akrotiri, Amnissos, Kamares, Ida, Dikte).
const PLANET_NAMES := {
	"minoa": ["Gournia", "Palaikastro", "Archanes", "Hagia Triada", "Tylissos", "Kommos", "Pseira", "Mochlos",
		"Vathypetro", "Myrtos", "Petras", "Galatas", "Monastiraki", "Zominthos", "Nirou Chani", "Katsambas", "Lebena",
		"Arkalochori", "Kydonia", "Juktas",
		"Eleutherna", "Aptera", "Lato", "Praisos", "Itanos", "Gortyn", "Prinias", "Sklavokampos", "Anemospilia", "Apodoulou",
		"Chamaizi", "Pyrgos", "Vasiliki", "Fournou Korifi", "Trypiti", "Kamilari"],
	"sparta": ["Gytheion", "Amyklai", "Therapne", "Pellana", "Sellasia", "Helos", "Kardamyle", "Tainaron", "Kythera",
		"Geronthrai", "Karyai", "Boiai", "Leuktra", "Oitylos", "Las", "Kotyrta", "Asopos", "Akriai", "Zarax", "Kyphanta",
		"Pephnos", "Leukai", "Aigys", "Belbina", "Kromnos", "Thalamai", "Gerenia", "Pharis", "Hyperteleaton", "Glympeis",
		"Marios", "Epidelion", "Kyparissia", "Teuthrone", "Pyrrhichos", "Kainepolis"],
	"mycenae": ["Tiryns", "Midea", "Dendra", "Nauplia", "Asine", "Lerna", "Prosymna", "Nemea", "Gla", "Iolkos",
		"Orchomenos", "Nichoria", "Argos", "Epidauros", "Korinthos", "Hermione", "Troizen", "Kleonai", "Methana", "Thebai",
		"Berbati", "Zygouries", "Kalkani", "Kazarma", "Aidonia", "Krisa", "Eutresis", "Dimini", "Pteleos", "Athikia",
		"Mases", "Aigina", "Phylakopi", "Kakovatos", "Peristeria", "Englianos"],
	"athens": ["Eleusis", "Sounion", "Brauron", "Rhamnous", "Dekeleia", "Phyle", "Thorikos", "Laurion", "Acharnai",
		"Kephisia", "Phaleron", "Aphidna", "Oropos", "Hymettos", "Kolonos", "Prasiai", "Salamis",
		"Anaphlystos", "Paiania", "Kerameikos", "Melite", "Kollytos", "Alopeke", "Kydathenaion", "Erchia", "Sphettos", "Halai",
		"Probalinthos", "Trikorynthos", "Oinoe", "Plotheia", "Ikaria", "Pallene", "Gargettos", "Lamptrai", "Myrrhinous", "Steiria"],
	"ionia": ["Priene", "Teos", "Erythrai", "Klazomenai", "Kolophon", "Lebedos", "Myous", "Phokaia", "Notion", "Didyma",
		"Chios", "Klaros", "Mykale", "Pygela", "Magnesia", "Panionion",
		"Kyme", "Larisa", "Pitane", "Myrina", "Aigai", "Temnos", "Sardeis", "Iasos", "Halikarnassos", "Knidos", "Kaunos",
		"Bargylia", "Euromos", "Mylasa", "Labraunda", "Herakleia", "Tralleis", "Nysa", "Lesbos", "Mytilene"],
	"cyclades": ["Sifnos", "Kea", "Serifos", "Sikinos", "Amorgos", "Folegandros", "Anafi", "Antiparos", "Donousa",
		"Schinoussa", "Iraklia", "Koufonisi", "Mykonos", "Tinos", "Andros", "Kythnos", "Polyaigos", "Despotiko", "Skarkos",
		"Akrotiraki", "Grotta", "Dokathismata", "Kapros", "Louros", "Aplomata", "Panormos", "Agia Irini", "Kephala Keos",
		"Ftelia", "Saliagos", "Zas", "Strofilas", "Vouni", "Kampos", "Dhaskalio", "Markiani"],
	"pirates": ["Sherden", "Shekelesh", "Tjeker", "Denyen", "Weshesh", "Teresh", "Ekwesh", "Peleset", "Dor", "Enkomi",
		"Kition", "Alashiya", "Karkisa", "Tarsa", "Ura", "Arzawa", "Sikila", "Lukki",
		"Aradus", "Sidon", "Tyros", "Byblos", "Gubla", "Amurru", "Tarhuntassa", "Mira", "Seha", "Hapalla", "Wilusa", "Masa",
		"Karkemish", "Kizzuwatna", "Tarsos", "Mersin", "Ashdod", "Lalanda"],
}
const BASE_LINKS := [["keros", "pylos"], ["keros", "miletos"], ["atrapos", "klotho"], ["atrapos", "lachesis"], ["atrapos", "delos"], ["klotho", "erebos"],
	["klotho", "nyx"], ["nyx", "erebos"], ["nyx", "hekate"], ["lachesis", "hekate"], ["lachesis", "tartaros"],
	["lachesis", "pylos"], ["delos", "kyros"], ["delos", "naxos"], ["kyros", "naxos"], ["kyros", "thera"],
	["kyros", "pylos"], ["thera", "pylos"], ["pylos", "tartaros"], ["naxos", "skylla"], ["thera", "skylla"],
	["hekate", "tartaros"], ["thera", "miletos"], ["miletos", "ephesos"], ["miletos", "samos"], ["ephesos", "samos"],
	["skylla", "ephesos"]]

## How many systems each empire holds once the galaxy is grown (6 to 12 each),
## and how many more pirate dens.
const EMPIRE_SIZE := {"minoa": 9, "athens": 10, "sparta": 9, "mycenae": 8, "ionia": 10, "cyclades": 8}
const EXTRA_DENS := 3
## The grown systems' names: the empire's further cities, lands and islands
## (any already a planet's, station's or system's name is skipped).
const SYSTEM_NAMES := {
	"minoa": ["Sitia", "Kissamos", "Lyttos", "Axos", "Phalasarna", "Elyros", "Lappa", "Knossia", "Hierapytna", "Priansos", "Rhaukos", "Biannos"],
	"athens": ["Chalkis", "Eretria", "Plataiai", "Megara", "Karystos", "Styra", "Tanagra", "Oinophyta", "Skione", "Amphipolis", "Potidaia", "Thasos Polis"],
	"sparta": ["Tegea", "Mantineia", "Ithome", "Megalopolis", "Phigaleia", "Elis", "Olympia", "Sikyon", "Phleious", "Kythera Gate", "Messene", "Pharai"],
	"mycenae": ["Argolis", "Perseia", "Danaia", "Pelopia", "Atreia", "Tirynthia", "Heraion", "Kalaureia", "Kenchreai", "Korakou", "Gonia", "Arne"],
	"ionia": ["Assos", "Adramyttion", "Kyzikos", "Lampsakos", "Abydos", "Sinope", "Trapezous", "Olbia", "Pantikapaion", "Massalia", "Elea", "Naukratis"],
	"cyclades": ["Melos", "Syros", "Naxia", "Paros", "Siphnos", "Keos", "Delos", "Thera Isle", "Pholegandros", "Kimolos", "Anaphe", "Ios"],
	"pirates": ["Shardana", "Tursha", "Danuna", "Weshwesh", "Tjekker"],
}

static var _grown: Array = []
static var SYSTEMS: Dictionary = _grow()[0]
static var LINKS: Array = _grow()[1]


## The galaxy grown from BASE_SYSTEMS: each empire spreads outward from its
## territory (away from the galaxy's middle) to EMPIRE_SIZE systems - each new
## one at least 100 from any other, its gate lane to the system it grew from
## crossing no other lane, and one more lane to a near neighbour where it can
## (loops, and contested borders). Deterministic (fixed seed): the same galaxy
## every game. Returns [systems, links] (cached).
static func _grow() -> Array:
	if not _grown.is_empty():
		return _grown
	var systems: Dictionary = BASE_SYSTEMS.duplicate(true)
	var links: Array = BASE_LINKS.duplicate(true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var used := {}
	for id in systems:
		used[systems[id]["name"]] = true
	for pool in [PLANET_NAMES, STATION_ROOTS]:
		for e in pool:
			for n in pool[e]:
				used[n] = true
	for n in INDEPENDENT_ROOTS:
		used[n] = true
	var centre := Vector2.ZERO
	for id in systems:
		centre += systems[id]["pos"]
	centre /= systems.size()
	var stars: Array = STARS.keys().filter(func(k): return k != "brown" and not STARS[k].get("rare", false))
	var want := EMPIRE_SIZE.duplicate()
	want["pirates"] = systems.values().filter(func(sy): return sy["owner"] == "pirates").size() + EXTRA_DENS
	var serial := 0
	var growing := true
	var rounds := 0
	while growing and rounds < 40:   # (an empire hemmed in stops short of its size)
		rounds += 1
		growing = false
		for e in want:
			var own: Array = systems.keys().filter(func(k): return systems[k]["owner"] == e)
			if own.size() >= want[e]:
				continue
			growing = true
			var best := {}
			for t in 120:
				var parent: String = own[rng.randi() % own.size()]
				var pp: Vector2 = systems[parent]["pos"]
				var out_dir := (pp - centre).normalized() if pp.distance_to(centre) > 1.0 else Vector2.RIGHT
				var p := pp + Vector2.from_angle(out_dir.angle() + rng.randf_range(-1.7, 1.7)) * rng.randf_range(115.0, 175.0)
				var near := INF
				var near_foreign := INF
				for k in systems:
					var d: float = p.distance_to(systems[k]["pos"])
					near = minf(near, d)
					if systems[k]["owner"] != e:
						near_foreign = minf(near_foreign, d)
				if near < 100.0 or _crosses(systems, links, pp, p):
					continue
				var score := minf(near_foreign, 400.0) - p.distance_to(pp) * 0.3 + rng.randf() * 30.0
				if best.is_empty() or score > best["score"]:
					best = {"pos": p, "parent": parent, "score": score}
			if best.is_empty():
				continue
			var name := ""
			for n in SYSTEM_NAMES.get(e, []):
				if not used.has(n):
					name = n
					break
			if name == "":
				name = "%s %d" % [EMPIRES[e]["short"], serial + 1]
			used[name] = true
			serial += 1
			var id := "g%d_%s" % [serial, name.to_lower().replace(" ", "_")]
			systems[id] = {"name": name, "pos": best["pos"], "owner": e, "star": stars[rng.randi() % stars.size()],
				"pirates": 1.0 if e == "pirates" else snappedf(rng.randf_range(0.15, 0.5), 0.05)}
			links.append([best["parent"], id])
			# One more lane, to the nearest system it can reach without crossing.
			var cands: Array = systems.keys().filter(func(k): return k != id and k != best["parent"])
			cands.sort_custom(func(a, b): return systems[a]["pos"].distance_to(best["pos"]) < systems[b]["pos"].distance_to(best["pos"]))
			for k in cands.slice(0, 3):
				var q: Vector2 = systems[k]["pos"]
				if q.distance_to(best["pos"]) < 210.0 and not _crosses(systems, links, best["pos"], q):
					links.append([id, k])
					break
	_grown = [systems, links]
	return _grown


## Does the lane a-b cross an existing lane (lanes sharing an end don't count)?
static func _crosses(systems: Dictionary, links: Array, a: Vector2, b: Vector2) -> bool:
	for l in links:
		var c: Vector2 = systems[l[0]]["pos"]
		var d: Vector2 = systems[l[1]]["pos"]
		if c.is_equal_approx(a) or c.is_equal_approx(b) or d.is_equal_approx(a) or d.is_equal_approx(b):
			continue
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
			return true
	return false


## Knossos (id "atrapos"): the hand-made home system (matches main.tscn and the quest).
const HOME_STATIONS := [
	{"name": "Knossos Station", "pos": Vector2(1300, -900), "economy": "trade_hub"},
	{"name": "Helios Dock", "pos": Vector2(-4200, -2700), "economy": "industrial"},
	{"name": "Kephala Outpost", "pos": Vector2(4600, 2900), "economy": "hi_tech"},
	{"name": "Nyx Relay", "pos": Vector2(-2600, 4700), "economy": "refinery"},
]
const GATE_RADIUS := 11000.0

var time := 0.0                    # galaxy clock (planet orbits use it)
var current_system := HOME
var systems := {}                  # id -> runtime system data (owner, planets, stations, gates, fields)
var stations := {}                 # station id -> {id, system, name, economy, pos, stock{}, last{}}
var rocks := {}                    # system id -> its asteroids as last left (depleted ones are gone for good)
var traders := {}                  # id -> trader record
var relations := {}                # "a|b" -> -100..100
var war := {}                      # "a|b" -> true when at war
var reputation := {"athens": 0.0, "sparta": 0.0, "minoa": 10.0, "mycenae": 0.0, "ionia": 0.0, "pirates": -100.0}
var news := []                     # [{t, text, kind}]
var route: Array = []              # player's planned route (system ids, from current)
## Fog of war in each star system: what your sensors have swept (FogOfWar,
## FOG_CELL world units a cell over FOG_EXTENT round the star), revealed
## SENSOR_RANGE round your ship; the system map shows only what's explored.
const FOG_EXTENT := 16000.0
const FOG_CELL := 400.0
const SENSOR_RANGE := 2800.0
var explored := {}                 # system id -> saved fog (base64)
var _fogs := {}                    # system id -> FogOfWar
var _all_seen := false             # (an old save, from before the fog: everything charted)
## Systems whose navigation beacon you've scanned (NavBeacon, by the star): its
## report made (NavReports) - the beacon shown alive. (It doesn't lift the fog.)
var charted := {}                  # system id -> true
## Navigation reports: system id -> the latest report of it (NavReports.make).
var reports := {}
## The jumps you've made (a beacon gives another report only after you've
## left and come back): report_issued[system id] = jumps when it last gave one.
var jumps := 0
var report_issued := {}
## Signal sources (SignalSites) per system: {"epoch": n, "list": [signal...]};
## a system scan locates them, you drop into them from their beacons.
var signals := {}
var active := false                # simulating (a game is loaded)

# Control: every system has a control strength that empires at war with its
# owner undermine (from their neighbouring systems, and harder from a forward
# base inside it); every CYCLE seconds a system worn down to nothing changes
# hands.
const CYCLE := 480.0
var _cycle := CYCLE

var _tick := 0.0
var _diplo := 60.0
var _states_cd := 90.0
var _spawn_cd := 5.0
var _next_id := 1
var _rng := RandomNumberGenerator.new()


# --- Setup -------------------------------------------------------------------------------

## `map_only`: just the map - systems, stations, planets - without the traders
## and the economy's warm-up (60 market ticks, ~0.9 s): for Talos's tools,
## which list the galaxy's places but never run it. A real game always starts
## its own (main.gd).
## A new game made across frames: the economy's warm-up (the slow part, ~0.9 s)
## a few milliseconds a frame - the loading screen keeps moving meanwhile;
## `progress(share)` follows it. The space scene then finds the galaxy ready
## (prepared) instead of making one in its first frame.
var prepared := false
const ASYNC_BUDGET_US := 4000
## `warm_later`: the economy's warm-up (60 rounds of trade, the stations'
## prices noted) left running in the background after the game starts - no
## waiting for it (a new game from the title: it was ~12 s of a loading screen).
func new_game_async(progress := Callable(), warm_later := false) -> void:
	active = false   # (the simulation waits until it's all there)
	_new_game_begin(true, false)   # (the map; the stations' stocks, the traders and the economy below, a little a frame)
	await get_tree().process_frame
	var t0 := Time.get_ticks_usec()
	for sid in stations:
		_stock_goods(stations[sid])
		if Time.get_ticks_usec() - t0 > ASYNC_BUDGET_US:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	price_cache = {}
	sell_sum = {}
	sell_n = {}
	for i in TRADER_TARGET:
		_spawn_trader()
		if Time.get_ticks_usec() - t0 > ASYNC_BUDGET_US:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	if warm_later:
		_new_game_end(true, true)   # (running now; prices noted as the warm-up finishes)
		prepared = true
		_warm_up_economy()   # (not waited for)
		return
	var ids := stations.keys()
	for i in 60:
		for sid in ids:
			_economy_tick_station(sid, false)
			if Time.get_ticks_usec() - t0 > ASYNC_BUDGET_US:
				if progress.is_valid():
					progress.call(i / 60.0)
				await get_tree().process_frame
				t0 = Time.get_ticks_usec()
	for sid in ids:
		_note_prices(sid)
		if Time.get_ticks_usec() - t0 > ASYNC_BUDGET_US:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()
	_new_game_end(true, true)
	prepared = true


## A new game's economy warmed up a little a frame while it's played (new_game_async's warm_later).
const WARM_BUDGET_US := 1500   # (a frame's share while the game is played)

func _warm_up_economy() -> void:
	var ids := stations.keys()
	var t0 := Time.get_ticks_usec()
	for i in 60:
		for sid in ids:
			if not stations.has(sid):
				return   # (another game started meanwhile)
			_economy_tick_station(sid, false)
			if Time.get_ticks_usec() - t0 > WARM_BUDGET_US:
				await get_tree().process_frame
				t0 = Time.get_ticks_usec()
	for sid in ids:
		if stations.has(sid):
			_note_prices(sid)
		if Time.get_ticks_usec() - t0 > WARM_BUDGET_US:
			await get_tree().process_frame
			t0 = Time.get_ticks_usec()


func new_game(announce := true, map_only := false) -> void:
	_new_game_begin(map_only)
	if not map_only:
		# Warm the economy up so prices and stocks start out lived-in (without
		# noting each tick's prices - every good priced afresh, uncached, was
		# 3.5 s of the new game's start; the trend starts from today's).
		for i in 60:
			_economy_tick(false)
	_new_game_end(announce, map_only)


## `stock`: the stations' goods stocked here too (new_game_async does it itself, a little a frame).
func _new_game_begin(map_only: bool, stock := true) -> void:
	prepared = false
	_rng.seed = 7
	time = 0.0
	current_system = HOME
	route = []
	news = []
	explored = {}
	_fogs = {}
	_all_seen = false
	charted = {}
	reports = {}
	jumps = 0
	report_issued = {}
	signals = {}
	traders = {}
	stations = {}
	systems = {}
	rocks = {}
	_next_id = 1
	destroyed_stations = []
	visited = {}
	seen = {}
	knowledge += 1
	reputation = {"athens": 0.0, "sparta": 0.0, "minoa": 10.0, "mycenae": 0.0, "ionia": 0.0, "cyclades": 0.0, "independent": 0.0, "pirates": -100.0}
	_diplo_last = 0.0
	relations = {}
	war = {}
	_set_relation("minoa", "sparta", 15.0)
	_set_relation("minoa", "athens", 30.0)
	_set_relation("minoa", "mycenae", 5.0)
	_set_relation("sparta", "mycenae", 45.0)
	_set_relation("sparta", "athens", -70.0)
	_set_relation("mycenae", "minoa", -35.0)
	_set_relation("ionia", "athens", 45.0)
	_set_relation("ionia", "minoa", 20.0)
	_set_relation("ionia", "sparta", -25.0)
	_set_relation("ionia", "mycenae", 0.0)
	_set_relation("cyclades", "minoa", 35.0)
	_set_relation("cyclades", "ionia", 20.0)
	_set_relation("cyclades", "athens", 10.0)
	_set_relation("cyclades", "sparta", -5.0)
	_set_relation("cyclades", "mycenae", -15.0)
	for e in MAJOR:
		_set_relation(e, "pirates", -100.0)
	_generate()
	_plan_goods()
	if stock:
		for sid in stations:
			_stock_goods(stations[sid])
	price_cache = {}
	sell_sum = {}
	sell_n = {}
	if not map_only:
		for i in TRADER_TARGET:
			_spawn_trader()


func _new_game_end(announce: bool, map_only: bool) -> void:
	if not map_only:
		for sid in stations:
			_note_prices(sid)
	Fleets.reset()
	active = true
	if announce:
		_post("Galactic news feed online. The Spartan Hegemony and the Minoan Thalassocracy are at war.", "news")


## A station's prices worked out and kept, and taken as its last ones (the
## market's trend starts from them).
func _note_prices(sid) -> void:
	cache_prices(sid)
	var row: Dictionary = price_cache.get(sid, {})
	for c in stations[sid]["stock"]:
		if row.has(c):
			stations[sid]["last"][c] = row[c][3]


## Counts the galaxy's planets as they're generated (their PlanetGen variant).
var _planet_serial := 0
var _seeds_used := {}


## A planet's surface seed, never one another planet has (the same draw as
## before; a repeat moves on to the next free one) - no two surfaces alike.
func _unique_seed(s: int) -> int:
	while _seeds_used.has(s) or s in [101, 202, 303, 404, 505]:   # (and not a home planet's)
		s += 1
	_seeds_used[s] = true
	return s

func _generate() -> void:
	_planet_serial = 0
	_seeds_used = {}
	planets = {}
	_names_used = {}
	_staples_used = {}
	_roots_used = {}
	_indie_used = 0
	added_stations = []
	for id in SYSTEMS:
		var d: Dictionary = SYSTEMS[id]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(id)
		var sys := {"id": id, "name": d["name"], "owner": d["owner"], "star": d["star"], "pirates": d["pirates"], "state": "none",
			"control": 60.0, "undermine": {},
			"planets": [], "stations": [], "gates": {}, "fields": []}
		# Gates: on the system's edge, in the direction of the neighbour on the map.
		for n in neighbors(id):
			var dir: Vector2 = (SYSTEMS[n]["pos"] - d["pos"]).normalized()
			sys["gates"][n] = dir * GATE_RADIUS
		if id == HOME:
			for i in HOME_STATIONS.size():
				_add_station(sys, HOME_STATIONS[i]["name"], HOME_STATIONS[i]["pos"], HOME_STATIONS[i]["economy"])
		else:
			_generate_system(sys, rng)
		systems[id] = sys
	# Guests (independents, allies' outposts): once every system's owner is known.
	for id in systems:
		if id != HOME:
			_generate_guests(systems[id])


const STATION_NAMES := {
	"athens": ["Agora", "Stoa", "Lyceum", "Harbour", "Akropolis", "Emporion"],
	"sparta": ["Bastion", "Agoge", "Arsenal", "Phalanx", "Barracks", "Citadel"],
	"minoa": ["Palace", "Labyrinth", "Sanctuary", "Harbour", "Archive", "Court"],
	"mycenae": ["Citadel", "Megaron", "Treasury", "Lion Gate", "Forge", "Tholos"],
	"ionia": ["Lyceum", "Observatory", "Garden Isle", "Agora", "Odeon", "Artemision"],
	"cyclades": ["Sanctuary", "Quarry", "Harbour", "Circle", "Beacon", "Workshop"],
	"pirates": ["Den", "Haven", "Wreckyard"]}
## What a generated system's other stations (after its first, named after
## the system) are named after: the empire's heroes, people, landmarks and
## cities - handed out in turn through its systems, none twice. (Not the
## story's people - Ariadne, Daidalos, Minos, Theseus - nor the ships' class
## names, nor any planet's or system's name.)
const STATION_ROOTS := {
	"athens": ["Pericles", "Solon", "Kleisthenes", "Themistokles", "Miltiades", "Sokrates", "Aristeides", "Kimon",
		"Kekrops", "Erechtheus", "Erechtheion", "Propylaia", "Pnyx", "Areopagos", "Lykabettos", "Pentelikon"],
	"sparta": ["Menelaos", "Helen", "Brasidas", "Agesilaos", "Lysandros", "Kastor", "Polydeukes", "Tyndareos",
		"Pausanias", "Archidamos", "Chilon", "Menelaion", "Taygetos", "Eurotas", "Amyklaion", "Orthia"],
	"minoa": ["Rhadamanthys", "Sarpedon", "Europa", "Idomeneus", "Phaidra", "Glaukos", "Androgeos", "Katreus",
		"Deukalion", "Meriones", "Britomartis", "Eileithyia", "Kouretes", "Psychro", "Skoteino", "Akakallis"],
	"mycenae": ["Atreus", "Perseus", "Orestes", "Elektra", "Herakles", "Nestor", "Diomedes", "Aias",
		"Achilleus", "Danae", "Eurystheus", "Pelops", "Iphigeneia", "Andromeda", "Kyklopes", "Tantalos"],
	"ionia": ["Anaximenes", "Pythagoras", "Homeros", "Sappho", "Anakreon", "Hekataios", "Hippodamos", "Aspasia",
		"Bias", "Xenophanes", "Hipponax", "Mimnermos", "Mausoleion", "Kolossos", "Smyrna", "Ion"],
	"cyclades": ["Anios", "Leto", "Apollo", "Dionysos", "Kynthos", "Rhoio", "Asteria", "Oino", "Spermo", "Elais",
		"Kernos", "Pyxis", "Chalandriani", "Kastri", "Spedos", "Plastiras"],
}
var _roots_used := {}               # empire -> station roots handed out so far


## The next station name root of an empire (a hero, person, landmark or city).
func _station_root(owner: String) -> String:
	var roots: Array = STATION_ROOTS.get(owner, STATION_ROOTS["athens"])
	var k: int = _roots_used.get(owner, 0)
	_roots_used[owner] = k + 1
	# (past the list: again with a Greek letter - "Pericles Beta" - so no two alike)
	var round := k / roots.size()
	return roots[k % roots.size()] if round == 0 else "%s %s" % [roots[k % roots.size()], ["Beta", "Gamma", "Delta", "Epsilon", "Zeta"][mini(round - 1, 4)]]


## Independent stations: a free port's name (an island of the old Aegean)
## and what it is.
const INDEPENDENT_ROOTS := ["Rhodos", "Lemnos", "Kerkyra", "Ithaka", "Kos", "Karpathos", "Skiathos", "Skyros",
	"Samothrake", "Imbros", "Zakynthos", "Kephallenia", "Leukas", "Symi", "Astypalaia", "Nisyros"]
const INDEPENDENT_KINDS := ["Free Port", "Waystation", "Exchange", "Freehold", "Caravanserai", "Commons"]
const INDEPENDENT_ECONOMIES := ["trade_hub", "mining", "agricultural", "refinery"]
var _indie_used := 0
## Foreign stations: at most this many in a system, and always fewer than the
## owner's own (the occupying empire keeps the majority).
const MAX_GUESTS := 2


## A system's guests besides its owner's stations (a separate random stream:
## the owner's stations, planets and fields stay as they were): often an
## independent free port; and an ally next door may keep an outpost there.
func _generate_guests(sys: Dictionary) -> void:
	if sys["owner"] == "pirates":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(sys["id"]) + "guests")
	if rng.randf() < 0.6:
		_add_guest(sys, "independent", rng.randf() * TAU, rng.randf_range(3500.0, 8500.0), INDEPENDENT_ECONOMIES[rng.randi() % INDEPENDENT_ECONOMIES.size()])
	for e in MAJOR:
		if e != sys["owner"] and relation(e, sys["owner"]) >= 40.0 and _borders(e, sys["id"]) and rng.randf() < 0.5:
			_add_guest(sys, e, rng.randf() * TAU, rng.randf_range(3500.0, 8500.0), "trade_hub")
			break


## Does `e` own a system next to `sys_id`?
func _borders(e: String, sys_id: String) -> bool:
	for n in neighbors(sys_id):
		if owner_of(n) == e:
			return true
	return false


## The stations in a system not run by its owner.
func guests_in(sys_id: String) -> Array:
	return system(sys_id).get("stations", []).filter(func(sid): return station_owner(sid) != owner_of(sys_id))


## May another station join this system and the owner still hold the majority?
func _room_for_guest(sys_id: String) -> bool:
	var all: Array = system(sys_id).get("stations", [])
	var guests := guests_in(sys_id).size()
	return guests < MAX_GUESTS and all.size() - guests > guests + 1


## Adds a station of `e` (an empire or "independent") to a system.
func _add_guest(sys: Dictionary, e: String, ang: float, dist: float, econ: String, force := false) -> Dictionary:
	if not force and not _room_for_guest(sys["id"]):
		return {}
	var label: String
	if e == "independent":
		label = "%s %s" % [INDEPENDENT_ROOTS[_indie_used % INDEPENDENT_ROOTS.size()], INDEPENDENT_KINDS[_indie_used % INDEPENDENT_KINDS.size()]]
		_indie_used += 1
	else:
		var kinds: Array = STATION_NAMES.get(e, STATION_NAMES["athens"])
		label = "%s %s" % [_station_root(e), kinds[_roots_used.get(e, 0) % kinds.size()]]
	return _add_station(sys, label, Vector2.from_angle(ang) * dist, econ, e)


## A generated system's second station: what feeds it, by owner, in turn
## through its systems (the Mycenaeans' first station is already a mine).
const STAPLES := {"cyclades": ["agricultural", "mining", "refinery"], "athens": ["agricultural", "mining", "refinery"], "sparta": ["agricultural", "mining", "refinery"],
	"mycenae": ["agricultural", "agricultural", "mining"], "minoa": ["agricultural", "mining", "agricultural"],
	"ionia": ["agricultural", "mining", "agricultural"]}
var _staples_used := {}
var _names_used := {}               # empire -> planet names handed out so far

## The next planet name of an empire (its lesser cities and places, in turn).
func _planet_name(owner: String) -> String:
	var pool: Array = PLANET_NAMES.get(owner, PLANET_NAMES["athens"])
	var k: int = _names_used.get(owner, 0)
	_names_used[owner] = k + 1
	# (past the list: again with a Greek letter - "Gournia Beta" - so no two alike)
	return pool[k % pool.size()] if k < pool.size() else "%s %s" % [pool[k % pool.size()], ["Beta", "Gamma", "Delta", "Epsilon", "Zeta", "Eta"][mini(k / pool.size() - 1, 5)]]


## A generated system's planets: 1 to 12, each one of the four landable types
## (Planets.TYPES: volcanic worlds near the star, ocean worlds in the middle,
## ice worlds and gas giants further out), some with moons (gas giants up to
## three). Each is a world you can land on: its type's surface with its own
## seed and name. Moons are named after their planet (Gournia I, II...).
## Orbits are spaced by what each planet takes up (its size and its moons'
## orbits); the gates sit beyond the last one.
const MAX_PLANETS := 12
const MOON_ODDS := {"ocean": 0.35, "ice": 0.3, "volcanic": 0.15, "gas_giant": 0.85}
const ROMAN := ["I", "II", "III"]
var planets := {}                   # generated planet / moon id -> its record (Planets.get_planet)


func _generate_planets(sys: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(sys["id"]) + ":planets")
	var n := rng.randi_range(1, MAX_PLANETS)
	var r := rng.randf_range(2200.0, 2800.0)
	var prev_reach := 0.0
	for i in n:
		var zone := float(i) / maxf(1.0, n - 1.0) if n > 1 else 0.5
		var type := _planet_type(rng, zone)
		var giant := type == "gas_giant"
		var size := rng.randf_range(1000.0, 1500.0) if giant else rng.randf_range(320.0, 820.0)
		var n_moons := 0
		if rng.randf() < MOON_ODDS[type]:
			n_moons = rng.randi_range(1, 3) if giant else 1
		var moon_reach := size / 2.0 + 260.0 * n_moons + 180.0 if n_moons > 0 else size / 2.0
		if i > 0:
			r += prev_reach + moon_reach + rng.randf_range(350.0, 900.0)
		prev_reach = moon_reach
		_planet_serial += 1
		var tpls: Array = Planets.TYPES[type]["templates"]
		var id := "%s_p%d" % [sys["id"], i]
		var pl := {"id": id, "system": sys["id"], "type": type, "name": _planet_name(sys["owner"]),
			"template": tpls[rng.randi() % tpls.size()], "variant": _planet_serial, "size": size,
			"orbit": r, "phase": rng.randf() * TAU, "seed": _unique_seed(rng.randi() % 100000), "moon_of": ""}
		sys["planets"].append(pl)
		planets[id] = pl
		for m in n_moons:
			_planet_serial += 1
			var mid := "%sm%d" % [id, m]
			var msize := rng.randf_range(150.0, 260.0)
			var moon := {"id": mid, "system": sys["id"], "type": "moon", "name": "%s %s" % [pl["name"], ROMAN[m]],
				"template": "barren", "variant": _planet_serial, "size": msize,
				"orbit": size / 2.0 + 200.0 + 260.0 * m + rng.randf_range(0.0, 60.0), "phase": rng.randf() * TAU,
				"seed": _unique_seed(rng.randi() % 100000), "moon_of": id}
			sys["planets"].append(moon)
			planets[mid] = moon
	# The gates: beyond the outermost planet (and its moons).
	var edge := maxf(GATE_RADIUS, r + prev_reach + 2000.0)
	for g in sys["gates"]:
		sys["gates"][g] = (sys["gates"][g] as Vector2).normalized() * edge


## A planet's type by how far out it is (zone 0: nearest the star, 1: furthest).
static func _planet_type(rng: RandomNumberGenerator, zone: float) -> String:
	var w: Dictionary
	if zone < 0.3:
		w = {"volcanic": 6, "ocean": 3, "ice": 1, "gas_giant": 0}
	elif zone < 0.65:
		w = {"volcanic": 1, "ocean": 5, "ice": 2, "gas_giant": 2}
	else:
		w = {"volcanic": 0, "ocean": 1, "ice": 4, "gas_giant": 5}
	var total := 0
	for k in w:
		total += w[k]
	var x := rng.randi() % total
	for k in w:
		x -= w[k]
		if x < 0:
			return k
	return "ocean"


## A generated planet's (or moon's) record, {} if `id` isn't one.
func planet_record(id: String) -> Dictionary:
	return planets.get(id, {})


## The random draws the old planet generation made (2-5 cosmetic planets):
## still made, so the stations and fields that follow stay where they were.
static func _old_planet_draws(rng: RandomNumberGenerator) -> void:
	var n := rng.randi_range(2, 5)
	rng.randf()
	for i in n:
		if i >= n - 2:
			rng.randf()   # outer?
		rng.randi()       # template
		for k in 4:       # size, phase, seed, the gap to the next
			rng.randf()


func _generate_system(sys: Dictionary, rng: RandomNumberGenerator) -> void:
	var name: String = sys["name"]
	_old_planet_draws(rng)
	_generate_planets(sys)
	var econs: Array
	match sys["owner"]:
		"pirates": econs = ["haven", "mining"]
		"sparta": econs = ["military", "industrial", "mining", "refinery", "agricultural"]
		"mycenae": econs = ["mining", "industrial", "agricultural", "refinery", "military"]
		"minoa": econs = ["hi_tech", "trade_hub", "hi_tech", "refinery", "agricultural"]
		"ionia": econs = ["hi_tech", "agricultural", "trade_hub", "hi_tech", "refinery"]
		"cyclades": econs = ["mining", "trade_hub", "agricultural", "hi_tech", "refinery"]
		_: econs = ["trade_hub", "agricultural", "industrial", "mining", "refinery", "hi_tech"]
	var n_st := 1 if sys["owner"] == "pirates" else rng.randi_range(2, 3)
	var name_start := rng.randi()
	for i in n_st:
		# The first station is the empire's signature, the second feeds the
		# system (food, ore or fuel - every inhabited system has staples
		# within a jump), a third is anything the empire builds.
		var econ: String = econs[0]
		if i == 1:
			# In turn through the empire's staples, so its systems feed each other.
			rng.randi()   # (keeps the generator's sequence: names and places stay put)
			var staples: Array = STAPLES.get(sys["owner"], STAPLES["athens"])
			var k: int = _staples_used.get(sys["owner"], 0)
			_staples_used[sys["owner"]] = k + 1
			econ = staples[k % staples.size()]
		elif i > 1:
			econ = econs[rng.randi() % econs.size()]
		var ang := rng.randf() * TAU
		var pos := Vector2.from_angle(ang) * rng.randf_range(3000.0, 8000.0)
		var names: Array = STATION_NAMES.get(sys["owner"], STATION_NAMES["athens"])
		# The first station bears the system's name; the others an empire's
		# hero, person, landmark or city ("Pericles Stoa", "Menelaion Bastion").
		var label := "%s %s" % [name if i == 0 else _station_root(sys["owner"]), names[(name_start + i) % names.size()]]
		if econ == "haven":
			label = "%s Raider Den" % name
		_add_station(sys, label, pos, econ)
	for i in rng.randi_range(1, 3):
		sys["fields"].append(Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3500.0, 9000.0))


func _add_station(sys: Dictionary, label: String, pos: Vector2, econ: String, empire := "") -> Dictionary:
	# (ids from a counter, not the count: a destroyed station's id is never reused)
	var n: int = sys.get("next_station", sys["stations"].size())
	sys["next_station"] = n + 1
	var id := "%s:%d" % [sys["id"], n]
	var st := {"id": id, "system": sys["id"], "name": label, "economy": econ, "pos": pos, "stock": {}, "last": {}, "impact": {},
		"empire": empire if empire != "" else str(sys["owner"]), "health": 100.0}
	var e: Dictionary = ECONOMIES[econ]
	for c in BASE_COMMODITIES:
		var base := 100.0
		if e["produce"].has(c):
			base = 160.0
		elif e["consume"].has(c):
			base = 25.0
		st["stock"][c] = base * _rng.randf_range(0.7, 1.3) if c != "alien_alloy" else (12.0 if e["produce"].has(c) else 2.0)
	sys["stations"].append(id)
	stations[id] = st
	if not _econ_goods.is_empty():
		_stock_goods(st)   # (a station added in play: its economy's goods too)
	return st


# --- Queries -----------------------------------------------------------------------------

static func neighbors(id: String) -> Array:
	var out := []
	for l in LINKS:
		if l[0] == id:
			out.append(l[1])
		elif l[1] == id:
			out.append(l[0])
	return out


func system(id: String) -> Dictionary:
	return systems.get(id, {})


func owner_of(id: String) -> String:
	return systems.get(id, {}).get("owner", HOME_EMPIRE)


func empire_name(e: String) -> String:
	return EMPIRES.get(e, {}).get("name", "Independent")


func empire_color(e: String) -> Color:
	return EMPIRES.get(e, {}).get("color", Color(0.7, 0.75, 0.8))


func _key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func relation(a: String, b: String) -> float:
	if a == b:
		return 100.0
	return relations.get(_key(a, b), 0.0)


func _set_relation(a: String, b: String, v: float) -> void:
	relations[_key(a, b)] = clampf(v, -100.0, 100.0)
	war[_key(a, b)] = relations[_key(a, b)] <= -50.0 or a == "pirates" or b == "pirates"


func state_of(id: String) -> String:
	return systems.get(id, {}).get("state", "none")


## Pirate activity 0..1+ (base level plus the Pirate Raids state).
func pirate_level(id: String) -> float:
	var sys: Dictionary = systems.get(id, {})
	return float(sys.get("pirates", 0.3)) + float(STATES[state_of(id)].get("pirates", 0.0))


## Demand label for the market (supply side): "high", "medium", "low".
func supply_level(station_id: String, item: String) -> String:
	var v: float = stations.get(station_id, {}).get("stock", {}).get(item, 0.0)
	var k := 10.0 if item == "alien_alloy" else 100.0
	if v > k * 1.6:
		return "high supply"
	if v < k * 0.35:
		return "scarce"
	return "medium supply"


func at_war(a: String, b: String) -> bool:
	if a == "" or b == "" or a == b:
		return false
	if a == "pirates" or b == "pirates":
		return true
	if a == "independent" or b == "independent":
		return false   # (independents keep out of every war)
	return war.get(_key(a, b), false)


## Allies: two major powers on good terms (relation 40+) and at peace - they
## answer each other's distress calls (Fleets.distress).
func allied(a: String, b: String) -> bool:
	return a != b and a in MAJOR and b in MAJOR and relation(a, b) >= 40.0 and not at_war(a, b)


func is_hostile_to_player(e: String) -> bool:
	return e == "pirates" or reputation.get(e, 0.0) <= HOSTILE_REP


## Your standing's tier with `e` ("Hostile" ... "Allied").
func standing(e: String) -> String:
	if e == "pirates":
		return "Hostile"
	var v: float = reputation.get(e, 0.0)
	var out: String = REP_TIERS[0][0]
	for t in REP_TIERS:
		if v >= t[1]:
			out = t[0]
	return out


## Reputation is earned slowly: every gain (missions, trade, bounties, rescues,
## quest rewards) counts this much of its amount; losses count in full.
const REP_GAIN := 0.1

## Changes your reputation with `e`; crossing into another tier is news.
func change_reputation(e: String, amount: float, why := "") -> void:
	if e == "" or e == "pirates" or amount == 0.0:
		return
	if amount > 0.0:
		amount *= REP_GAIN
	var before := standing(e)
	reputation[e] = clampf(reputation.get(e, 0.0) + amount, -100.0, 100.0)
	var now := standing(e)
	if now == before:
		return
	knowledge += 1   # (Friendly or not: whose markets you know changes)
	var up := REP_TIERS.map(func(t): return t[0]).find(now) > REP_TIERS.map(func(t): return t[0]).find(before)
	var who := empire_name(e)
	if now == "Hostile":
		_post("The %s now considers you an enemy%s - their warships will attack and their stations refuse you." % [who, (" (" + why + ")") if why != "" else ""], "danger")
	elif before == "Hostile":
		_post("The %s no longer treats you as an enemy (Unfriendly)." % who, "good")
	else:
		_post("Your standing with the %s: %s%s." % [who, now, (" (" + why + ")") if why != "" and not up else ""], "good" if up else "danger")


## A bad name fades: negative reputation drifts back toward 0 (REP_RECOVER a minute).
func _recover_reputation(minutes: float) -> void:
	for e in reputation:
		if e != "pirates" and reputation[e] < 0.0:
			reputation[e] = minf(0.0, reputation[e] + REP_RECOVER * minutes)


## A station's condition, 0..100 (an invasion's fleets wear it down; it
## mends slowly - Fleets - and faster with repair missions). Below
## DAMAGED it burns and offers only repair and defence missions; at 0 it is
## destroyed for good (destroy_station).
const DAMAGED := 40.0
var destroyed_stations: Array = []   # ids, in order (saved: they stay gone)
## What you know of the markets (trade routes, Market hints): stations you've
## docked at (visited) and ones you've seen (come within sensor range);
## an empire you're Friendly with shares all of its own. knowledge bumps when
## either grows (TradeRoutes' caches follow it).
var visited := {}
var seen := {}
var knowledge := 0


func station_health(station_id: String) -> float:
	return float(stations.get(station_id, {}).get("health", 100.0))


func damage_station(station_id: String, amount: float) -> void:
	var st: Dictionary = stations.get(station_id, {})
	if st.is_empty():
		return
	var before: float = st.get("health", 100.0)
	# (the home system's stations - the story's - can burn but never fall)
	st["health"] = clampf(before - amount, 10.0 if st["system"] == HOME else 0.0, 100.0)
	if before >= DAMAGED and st["health"] < DAMAGED:
		_post("%s, %s: the %s station is burning - it asks for repairs and defenders." % [st["name"], systems[st["system"]]["name"], EMPIRES.get(station_owner(station_id), {}).get("short", "")], "danger" if st["system"] == current_system else "news")
	if st["health"] <= 0.0:
		destroy_station(station_id)


func repair_station(station_id: String, amount: float) -> void:
	var st: Dictionary = stations.get(station_id, {})
	if not st.is_empty():
		st["health"] = clampf(float(st.get("health", 100.0)) + amount, 0.0, 100.0)


## Gone for good: out of its system and the galaxy (the game removes its node).
signal station_destroyed(station_id: String)

func destroy_station(station_id: String) -> void:
	var st: Dictionary = stations.get(station_id, {})
	if st.is_empty():
		return
	_post("DESTROYED: %s in %s - the %s has lost a station." % [st["name"], systems[st["system"]]["name"], empire_name(station_owner(station_id))], "danger")
	systems[st["system"]]["stations"].erase(station_id)
	stations.erase(station_id)
	_uncache(station_id)
	destroyed_stations.append(station_id)
	_rehome_traders(station_id, str(st["system"]))
	station_destroyed.emit(station_id)


## Traders based at a station that's gone, or bound for it: another station
## (in its system if one's left) - a docked one is lost with it.
func _rehome_traders(station_id: String, system_id: String) -> void:
	var sys_left: Array = systems.get(system_id, {}).get("stations", [])
	for id in traders.keys():
		var r: Dictionary = traders[id]
		if r.get("station", "") == station_id and r["state"] == "docked" and not r.get("live", false):
			traders.erase(id)
			continue
		if stations.is_empty():
			continue
		var other: String = sys_left[_rng.randi() % sys_left.size()] if not sys_left.is_empty() else stations.keys()[_rng.randi() % stations.size()]
		if r.get("station", "") == station_id:
			r["station"] = other
		if r.get("dest", "") == station_id:
			r["dest"] = other


func visit_station(station_id: String) -> void:
	if station_id != "" and not visited.has(station_id):
		visited[station_id] = true
		seen[station_id] = true
		knowledge += 1


func see_station(station_id: String) -> void:
	if station_id != "" and not seen.has(station_id):
		seen[station_id] = true
		knowledge += 1


## Shares its market with you: Friendly or better with its owner.
func shares_market(station_id: String) -> bool:
	return standing(station_owner(station_id)) in ["Friendly", "Allied"]


## You know its prices well enough to trade from it (docked there, or its
## owner shares them).
func knows_market(station_id: String) -> bool:
	return visited.has(station_id) or shares_market(station_id)


## You know it's there (seen, docked, or its owner shares its markets).
func knows_station(station_id: String) -> bool:
	return seen.has(station_id) or visited.has(station_id) or shares_market(station_id)


## Who runs a station (its own empire: not always the system's owner).
func station_owner(station_id: String) -> String:
	var st: Dictionary = stations.get(station_id, {})
	if st.is_empty():
		return HOME_EMPIRE
	return st.get("empire", owner_of(st["system"]))


## What a station is in its system: "" (the owner's), "independent",
## "outpost" (an ally's, by the owner's leave) or "forward" (a base of an
## empire at war with the owner, there to take the system).
func station_presence(station_id: String) -> String:
	var st: Dictionary = stations.get(station_id, {})
	if st.is_empty():
		return ""
	var e := station_owner(station_id)
	if e == owner_of(st["system"]):
		return ""
	if e == "independent":
		return "independent"
	return "forward" if at_war(e, owner_of(st["system"])) else "outpost"


static func presence_label(p: String) -> String:
	return {"independent": "independent", "outpost": "allied outpost", "forward": "forward base"}.get(p, "")


## Every station's prices as of its last economy tick (or your last trade
## there): station id -> {item -> [buy, sell, stock]}. Kept up as the stations
## tick (spread over frames), so reading every price of the galaxy - the
## market, the trade routes - costs nothing.
var price_cache := {}
## Running totals of the cached sell prices, per good, and how many stations
## deal in it: the galactic average without adding up every station's goods
## (~10,000 with the 140 goods - that was 12 ms a second).
var sell_sum := {}
var sell_n := {}


func cache_prices(station_id: String) -> void:
	var st: Dictionary = stations.get(station_id, {})
	if st.is_empty():
		return
	# (price()'s sum for every good the station deals in, with what's the same
	# for all of them worked out once - this runs for every station every tick)
	var rp := rep_prices(station_id)
	var buy_k: float = 1.08 * rp[0]
	var sell_k: float = 0.92 * rp[1]
	var at_war := _empire_at_war(station_owner(station_id))
	var demand: Dictionary = STATES[state_of(st["system"])].get("demand", {})
	var imp: Dictionary = st.get("impact", {})
	var stock: Dictionary = st["stock"]
	var row := {}
	var old: Dictionary = price_cache.get(station_id, {})
	var kept := 0   # (goods in both the old row and the new: the averages' totals move by the difference)
	for c in stock:
		var base: float = Items.ITEMS.get(c, {}).get("value", 10)
		var p := base * clampf(1.7 - 0.7 * stock[c] / (10.0 if c == "alien_alloy" else 100.0), 0.4, 2.4)
		if imp.has(c):
			p *= exp(float(imp[c]))
		if at_war and c in WAR_GOODS:
			p *= 1.25
		var dem: float = demand.get(c, 1.0)
		if dem > 1.0:
			p *= 1.0 + (dem - 1.0) * 0.35
		var sell := maxi(1, roundi(p * sell_k))
		row[c] = [maxi(1, roundi(p * buy_k)), sell, float(stock[c]), p]
		if old.has(c):
			sell_sum[c] += sell - old[c][1]
			kept += 1
		else:
			sell_sum[c] = float(sell_sum.get(c, 0.0)) + sell
			sell_n[c] = int(sell_n.get(c, 0)) + 1
	if kept < old.size():   # (a good it no longer deals in: out of the totals)
		for c in old:
			if not row.has(c):
				sell_sum[c] -= old[c][1]
				sell_n[c] -= 1
	price_cache[station_id] = row


## Drops a station's cached prices (and their share of the averages).
func _uncache(station_id: String) -> void:
	var old: Dictionary = price_cache.get(station_id, {})
	for c in old:
		sell_sum[c] = float(sell_sum.get(c, 0.0)) - old[c][1]
		sell_n[c] = int(sell_n.get(c, 0)) - 1
	price_cache.erase(station_id)


## The galactic average sell price of a good (0 if no station deals in it).
func average_sell(item: String) -> float:
	var n := int(sell_n.get(item, 0))
	return float(sell_sum.get(item, 0.0)) / n if n > 0 else 0.0


## Price of a commodity at a station (fluid: follows stock).
func price(station_id: String, item: String) -> float:
	var st: Dictionary = stations.get(station_id, {})
	var base: float = Items.ITEMS.get(item, {}).get("value", 10)
	if st.is_empty():
		return base
	var ratio: float = st["stock"].get(item, 40.0) / (100.0 if item != "alien_alloy" else 10.0)
	var p := base * clampf(1.7 - 0.7 * ratio, 0.4, 2.4)
	# Your recent trades here (see PLAYER_IMPACT).
	p *= exp(float(st.get("impact", {}).get(item, 0.0)))
	# Wartime: weapons, fuel and medicine are in demand in warring empires.
	var owner := station_owner(station_id)
	if item in WAR_GOODS and _empire_at_war(owner):
		p *= 1.25
	var dem: float = STATES[state_of(st["system"])].get("demand", {}).get(item, 1.0)
	if dem > 1.0:
		p *= 1.0 + (dem - 1.0) * 0.35
	return p


func buy_price(station_id: String, item: String) -> int:    # player buys
	return maxi(1, roundi(price(station_id, item) * 1.08 * rep_prices(station_id)[0]))


func sell_price(station_id: String, item: String) -> int:   # player sells
	return maxi(1, roundi(price(station_id, item) * 0.92 * rep_prices(station_id)[1]))


## [buy, sell] price multipliers at a station from your standing with its owner.
func rep_prices(station_id: String) -> Array:
	return REP_PRICES.get(standing(station_owner(station_id)), [1.0, 1.0])


## The pirate bounty multiplier your standing with `e` earns.
func bounty_bonus(e: String) -> float:
	return REP_BOUNTY.get(standing(e), 1.0)


## Price trend since the last economy tick: -1, 0, 1.
func trend(station_id: String, item: String) -> int:
	var st: Dictionary = stations.get(station_id, {})
	if st.is_empty():
		return 0
	var now := price(station_id, item)
	var before: float = st["last"].get(item, now)
	if now > before * 1.01:
		return 1
	if now < before * 0.99:
		return -1
	return 0


func _empire_at_war(e: String) -> bool:
	for o in MAJOR:
		if o != e and at_war(e, o):
			return true
	return false


## Shortest gate route from a to b (system ids, including both), avoiding
## systems of empires at war with `empire` (if given). [] if none.
func find_route(a: String, b: String, empire := "") -> Array:
	if a == b:
		return [a]
	var prev := {a: ""}
	var queue := [a]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		for n in neighbors(cur):
			if prev.has(n):
				continue
			if empire != "" and n != b and (at_war(empire, owner_of(n)) or owner_of(n) == "pirates"):
				continue
			prev[n] = cur
			if n == b:
				var path := [b]
				while path[0] != a:
					path.push_front(prev[path[0]])
				return path
			queue.append(n)
	return []


func station_by_name(system_id: String, label: String) -> Dictionary:
	for sid in systems.get(system_id, {}).get("stations", []):
		if stations[sid]["name"] == label:
			return stations[sid]
	return {}


# --- TradeGoods' goods ---------------------------------------------------------------------

## The rates TradeGoods' goods are made and used at, for this galaxy: each
## maker station makes a good at a rate by its value (cheap goods flow
## faster); its users, all together, use 80% of what its makers make - so the
## galaxy has a surplus to trade. Run after the stations exist (new game, load).
func _plan_goods() -> void:
	var count := {}
	for sid in stations:
		var e: String = stations[sid]["economy"]
		count[e] = int(count.get(e, 0)) + 1
	_econ_goods = {}
	for e in ECONOMIES:
		_econ_goods[e] = {"produce": {}, "consume": {}}
	for id in TradeGoods.GOODS:
		var makers: Array = ECONOMIES.keys().filter(func(e): return id in TradeGoods.MAKES.get(e, []))
		var users: Array = ECONOMIES.keys().filter(func(e): return id in TradeGoods.USES.get(e, []))
		var n_make := 0
		var n_use := 0
		for e in makers:
			n_make += int(count.get(e, 0))
		for e in users:
			n_use += int(count.get(e, 0))
		var make := clampf(40.0 / sqrt(float(TradeGoods.GOODS[id]["value"])), 0.3, 3.0)
		for e in makers:
			_econ_goods[e]["produce"][id] = make
		if n_use > 0 and n_make > 0:
			for e in users:
				_econ_goods[e]["consume"][id] = 0.8 * make * n_make / n_use


## Whether stations of economy `econ` make good `c` (the original goods and TradeGoods').
func makes(econ: String, c: String) -> bool:
	return ECONOMIES[econ]["produce"].has(c) or _econ_goods.get(econ, {}).get("produce", {}).has(c)


## Whether stations of economy `econ` use good `c`.
func uses(econ: String, c: String) -> bool:
	return ECONOMIES[econ]["consume"].has(c) or _econ_goods.get(econ, {}).get("consume", {}).has(c)


## Puts the goods a station's economy makes or uses into its stock (if
## missing): well stocked where made, some where used.
func _stock_goods(st: Dictionary) -> void:
	var g: Dictionary = _econ_goods.get(st["economy"], {})
	for c in g.get("produce", {}):
		if not st["stock"].has(c):
			st["stock"][c] = 160.0 * _rng.randf_range(0.7, 1.3)
	for c in g.get("consume", {}):
		if not st["stock"].has(c):
			st["stock"][c] = 60.0 * _rng.randf_range(0.7, 1.3)


# --- Simulation --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not active:
		return
	time += delta
	_tick -= delta
	if _tick <= 0.0:
		_tick = TICK
		_eco_queue.append_array(stations.keys())   # (any left from the last round first)
		_eco_round = _eco_queue.size()
	# (Each economy tick spread evenly over the TICK, by time - all at once was
	# a 2-3 ms frame every 2 s; two a frame bunched it into the first frames,
	# the slowest 5% of them at 600 FPS. At most ECO_PER_FRAME a frame.)
	_eco_acc += _eco_round * delta / TICK
	var n := 0
	while not _eco_queue.is_empty() and n < ECO_PER_FRAME and _eco_acc >= 1.0:
		_eco_acc -= 1.0
		var sid = _eco_queue.pop_back()
		if stations.has(sid):
			_economy_tick_station(sid)
			cache_prices(sid)
		n += 1
	_eco_acc = minf(_eco_acc, float(ECO_PER_FRAME))   # (no backlog building up while the queue is empty)
	_advance_traders(delta)
	_diplo -= delta
	if _diplo <= 0.0:
		_diplo = _rng.randf_range(70.0, 130.0)
		_diplomacy_tick()
	_states_cd -= delta
	if _states_cd <= 0.0:
		_states_cd = _rng.randf_range(90.0, 160.0)
		_states_tick()
	_cycle -= delta
	if _cycle <= 0.0:
		_cycle = CYCLE
		_control_cycle()
	_spawn_cd -= delta
	if _spawn_cd <= 0.0:
		_spawn_cd = 25.0
		if traders.size() < TRADER_TARGET:
			_spawn_trader()


const ECO_PER_FRAME := 2   # (stations a frame: ~60 goods each, ~0.2 ms a station)
var _eco_queue: Array = []
var _eco_round := 0        # stations in this round
var _eco_acc := 0.0        # stations due (fractional: by time)

## Every station's economy, at once (the game spreads it: _process).
## `note`: each good's price kept as its last (the market's trend arrows).
func _economy_tick(note := true) -> void:
	for sid in stations:
		_economy_tick_station(sid, note)


func _economy_tick_station(sid, note := true) -> void:
	var st: Dictionary = stations[sid]
	var e: Dictionary = ECONOMIES[st["economy"]]
	var war_mult := WAR_DEMAND if _empire_at_war(owner_of(st["system"])) else 1.0
	var state: Dictionary = STATES[state_of(st["system"])]
	var row: Dictionary = price_cache.get(sid, {})
	if note:
		for c in st["stock"]:
			st["last"][c] = row[c][3] if row.has(c) else price(sid, c)
	# Your market footprint fades.
	var imp: Dictionary = st.get("impact", {})
	for c in imp.keys():
		imp[c] *= IMPACT_DECAY
		if absf(imp[c]) < 0.002:
			imp.erase(c)
	# Production chain: output scales with the inputs in stock.
	var eff := 1.0
	for inp in INPUTS.get(st["economy"], []):
		eff = minf(eff, clampf(st["stock"].get(inp, 0.0) / 40.0, 0.0, 1.0))
	# A station short of its inputs also uses less (fewer shifts, idle
	# yards): starved chains slow down instead of spiralling to empty.
	var use := 0.5 + 0.5 * eff
	eff = (0.25 + 0.75 * eff) * float(state.get("produce", 1.0))
	st["efficiency"] = eff
	for c in e["produce"]:
		st["stock"][c] = minf(320.0 if c != "alien_alloy" else 30.0, st["stock"][c] + e["produce"][c] * TICK * RATE * eff)
	for c in e["consume"]:
		var m: float = (war_mult if c in WAR_GOODS else 1.0) * use
		m *= float(state.get("demand", {}).get(c, 1.0))
		st["stock"][c] = maxf(0.0, st["stock"][c] - e["consume"][c] * TICK * RATE * m)
	# TradeGoods' goods: made and used at this galaxy's rates (_plan_goods).
	var g: Dictionary = _econ_goods.get(st["economy"], {})
	var gp: Dictionary = g.get("produce", {})
	var gc: Dictionary = g.get("consume", {})
	for c in gp:
		st["stock"][c] = minf(320.0, float(st["stock"].get(c, 0.0)) + gp[c] * TICK * RATE * eff)
	for c in gc:
		st["stock"][c] = maxf(0.0, float(st["stock"].get(c, 0.0)) - gc[c] * TICK * RATE * use)
	# State demand also hits goods the station doesn't normally use.
	for c in state.get("demand", {}):
		if not e["consume"].has(c):
			st["stock"][c] = maxf(0.0, st["stock"][c] - 1.2 * RATE * TICK * float(state["demand"][c]))
	# Goods a station neither makes nor uses drift toward a modest level.
	for c in st["stock"]:
		if not e["produce"].has(c) and not e["consume"].has(c) and not gp.has(c) and not gc.has(c):
			var rest := 100.0 if c != "alien_alloy" else 10.0   # at its base price
			st["stock"][c] = move_toward(st["stock"][c], rest, 0.15)


# --- Traders -----------------------------------------------------------------------------

## Civil roles of trader ships and how common they are.
const TRADER_TYPES := [["trader", 0.6], ["miner", 0.25], ["explorer", 0.15]]
## Role names used by older save games.
const OLD_ROLES := {"cargo_hauler": "trader", "mining_ship": "miner"}
const SHIP_NAMES := ["Argo", "Kalypso", "Thetis", "Nereid", "Halcyon", "Meltemi", "Pegasus", "Triton", "Zephyr",
	"Amphitrite", "Hermes", "Iris", "Pleiad", "Kamares", "Astraea", "Penelope", "Ariadne", "Medea", "Orion", "Kestrel"]

func _spawn_trader(at_station := "") -> Dictionary:
	if at_station == "":
		var options := []
		for sid in stations:
			if station_owner(sid) != "pirates":
				options.append(sid)
		at_station = options[_rng.randi() % options.size()]
	var st: Dictionary = stations[at_station]
	var pick := _rng.randf()
	var role_name := "trader"
	for t in TRADER_TYPES:
		pick -= t[1]
		if pick <= 0.0:
			role_name = t[0]
			break
	# Fly the owning empire's own designs when it has them.
	var emp := station_owner(at_station)   # (an independent port's traders are independent)
	var type_id := ShipDesigns.pick(emp, [role_name])
	var id := "t%d" % _next_id
	_next_id += 1
	var rec := {"id": id, "type": type_id, "empire": emp,
		"name": SHIP_NAMES[_rng.randi() % SHIP_NAMES.size()], "cargo": {}, "credits": _rng.randi_range(600, 1600),
		"capacity": 60 if role_name == "trader" else (40 if role_name == "miner" else 15),
		"role": role_name,
		"system": st["system"], "state": "docked", "station": at_station, "wait": _rng.randf_range(2.0, 40.0),
		"legs": [], "t": 0.0, "live": false, "dest": ""}
	traders[id] = rec
	return rec


const TRADER_SLICES := 4      # the abstract traders advanced at most a quarter a frame, round robin
const TRADER_ROUND := 0.5     # s to go round them all
var _trader_ids: Array = []   # (this round's order)
var _trader_cursor := 0
var _trader_at := {}          # id -> galaxy time it was last advanced to


## The traders not flown by the game move along their routes - a slice of them
## a frame, each by the time since its own last turn (all 110 every frame was
## the costliest script of a frame: ~0.3-0.5 ms).
func _advance_traders(_delta: float) -> void:
	if _trader_cursor >= _trader_ids.size():
		_trader_ids = traders.keys()
		_trader_cursor = 0
		if _trader_at.size() > traders.size() + 32:   # (the ones gone since)
			for id in _trader_at.keys():
				if not traders.has(id):
					_trader_at.erase(id)
	# (a share of them a frame by time: round them all every TRADER_ROUND s -
	# a quarter a frame was each one 150 times a second at 600 FPS)
	var share := maxi(1, ceili(_trader_ids.size() * _delta / TRADER_ROUND))
	var end := mini(_trader_cursor + mini(share, ceili(_trader_ids.size() / float(TRADER_SLICES))), _trader_ids.size())
	var departed := false
	for j in range(_trader_cursor, end):
		var id = _trader_ids[j]
		var r: Dictionary = traders.get(id, {})
		if r.is_empty():
			_trader_at.erase(id)
			continue
		var delta := clampf(time - float(_trader_at.get(id, time - _delta)), 0.0, 10.0)
		_trader_at[id] = time
		if r["live"]:
			continue   # flown by the game; it reports arrivals
		if r["state"] == "docked":
			r["wait"] -= delta
			if r["wait"] <= 0.0 and not departed:
				departed = true   # (one a frame: planning a run prices the market - a few at once was a spike)
				_depart(r)
			continue
		if r["legs"].is_empty():
			_arrive(r)
			continue
		var leg: Dictionary = r["legs"][0]
		var length := maxf(Vector2(leg["from"][0], leg["from"][1]).distance_to(Vector2(leg["to"][0], leg["to"][1])), 1.0)
		r["t"] += delta * TRADER_SPEED / length
		# Pirates prey on ships in transit.
		var p: float = pirate_level(leg["system"]) * 0.0011
		if not r["cargo"].is_empty() and _rng.randf() < p * delta:
			_hijack_abstract(r, leg["system"])
		if r["t"] >= 1.0:
			leg_done(id)
	_trader_cursor = end


## The trader finished its current leg (abstractly, or its ship got there).
func leg_done(id: String) -> void:
	var r: Dictionary = traders.get(id, {})
	if r.is_empty() or r["legs"].is_empty():
		return
	var leg: Dictionary = r["legs"].pop_front()
	r["t"] = 0.0
	if r["legs"].is_empty():
		_arrive(r)
		return
	# Jumped through a gate: now in the next system.
	r["system"] = r["legs"][0]["system"]
	if r["system"] == current_system and not r["live"]:
		trader_appeared.emit(r)


func _arrive(r: Dictionary) -> void:
	r["state"] = "docked"
	r["station"] = r["dest"] if r["dest"] != "" else r["station"]
	r["system"] = stations[r["station"]]["system"]
	r["live"] = false
	var st: Dictionary = stations[r["station"]]
	# Sell everything aboard.
	for c in r["cargo"].keys():
		var n: int = r["cargo"][c]
		r["credits"] += roundi(price(st["id"], c) * 0.92) * n
		st["stock"][c] = st["stock"].get(c, 0.0) + n
	r["cargo"].clear()
	r["credits"] = maxi(r["credits"], 300)   # empires keep their merchants afloat
	r["wait"] = _rng.randf_range(5.0, 15.0)


func _depart(r: Dictionary) -> void:
	if not stations.has(r["station"]):
		# (its station was destroyed - in a save made before the traders were
		# moved on: it would fail here every frame and hold up every other
		# trader's departure) - lost with it.
		traders.erase(r.get("id", ""))
		for id in traders.keys():
			if traders[id] == r:
				traders.erase(id)
		return
	var from: Dictionary = stations[r["station"]]
	var plan := _plan_trade(r, from)
	var dest: Dictionary = plan["dest"]
	var item: String = plan["item"]
	if item != "":
		var bp := price(from["id"], item) * 1.08
		var qty := mini(int(r["capacity"]), mini(int(from["stock"][item] * 0.4), int(r["credits"] / bp)))
		if qty > 0:
			from["stock"][item] -= qty
			r["credits"] -= roundi(bp * qty)
			r["cargo"][item] = r["cargo"].get(item, 0) + qty
	# Legs: station -> gate -> ... -> gate -> station.
	var path := find_route(from["system"], dest["system"], r["empire"])
	if path.is_empty():
		path = [from["system"]]
		dest = from if systems[from["system"]]["stations"].size() < 2 else stations[systems[from["system"]]["stations"].pick_random()]
	var legs := []
	var pos: Vector2 = from["pos"]
	for i in path.size():
		var sys_id: String = path[i]
		var to: Vector2
		if i < path.size() - 1:
			to = systems[sys_id]["gates"][path[i + 1]]
		else:
			to = dest["pos"]
		legs.append({"system": sys_id, "from": [pos.x, pos.y], "to": [to.x, to.y]})
		if i < path.size() - 1:
			pos = systems[path[i + 1]]["gates"][sys_id]
	r["legs"] = legs
	r["dest"] = dest["id"]
	r["state"] = "travel"
	r["t"] = 0.0
	r["system"] = from["system"]
	if r["system"] == current_system:
		trader_appeared.emit(r)


## Best trade from this station: buy where cheap, sell where dear, per unit
## of travel. Looks at stations in this system and the neighbouring ones.
func _plan_trade(r: Dictionary, from: Dictionary) -> Dictionary:
	var best := {"item": "", "dest": from, "score": 0.0}
	var reach := [from["system"]]
	for n in neighbors(from["system"]):
		if not at_war(r["empire"], owner_of(n)) and owner_of(n) != "pirates":
			reach.append(n)
	if r.get("role", r["type"]) == "explorer":   # explorers wander
		# (to a system that still has a station: a war can burn them all -
		# picking from an empty list failed the departure every time)
		var options: Array = []
		for sys in reach:
			for sid in systems[sys]["stations"]:
				if stations.has(sid):
					options.append(sid)
		if not options.is_empty():
			best["dest"] = stations[options[_rng.randi() % options.size()]]
		return best
	# (prices from the cache - every station's, kept each economy tick: a full
	# price() per good and destination was thousands of calls a departure,
	# up to 14 ms with ~60 goods a station)
	var miner: bool = r.get("role", "") == "miner"
	var from_row: Dictionary = price_cache.get(from["id"], {})
	if from_row.is_empty():
		cache_prices(from["id"])
		from_row = price_cache.get(from["id"], {})
	var goods := []   # [good, its buy cost here, how much there is]
	for c in from["stock"]:
		var st: float = from["stock"][c]
		if st < 12.0 or (miner and not c.ends_with("_ore")) or not from_row.has(c):
			continue
		goods.append([c, from_row[c][3] * 1.08, st])
	var cap: float = r["capacity"]
	for sys in reach:
		for sid in systems[sys]["stations"]:
			if sid == from["id"] or not stations.has(sid):
				continue
			var d: Dictionary = stations[sid]
			var row: Dictionary = price_cache.get(sid, {})
			if row.is_empty():
				cache_prices(sid)
				row = price_cache.get(sid, {})
			var dstock: Dictionary = d["stock"]
			var econ: String = d["economy"]
			var travel: float = (from["pos"].distance_to(d["pos"]) if sys == from["system"] else 14000.0 + d["pos"].length()) / TRADER_SPEED + 30.0
			for g in goods:
				var c: String = g[0]
				if not row.has(c):
					continue
				var profit: float = row[c][3] * 0.92 - g[1]
				if profit <= 0.0:
					continue
				# Supply contracts: empires pay haulers to keep their stations
				# stocked, so a good the destination uses and is short of
				# counts for more than its margin alone (cheap food matters).
				if uses(econ, c):
					var short := clampf(1.0 - dstock[c] / 60.0, 0.0, 1.0)
					profit += NEED_PREMIUM * short * float(Items.ITEMS[c]["value"]) + NEED_FLAT * short
				var score := profit * minf(cap, g[2] * 0.4) / travel
				score *= _rng.randf_range(0.8, 1.2)   # some variety
				if score > best["score"]:
					best = {"item": c, "dest": d, "score": score}
	if best["item"] == "":
		var options: Array = systems[from["system"]]["stations"]
		best["dest"] = stations[options[_rng.randi() % options.size()]]
	return best


func _hijack_abstract(r: Dictionary, sys_id: String) -> void:
	var stolen := []
	for c in r["cargo"].keys():
		var n: int = ceili(r["cargo"][c] * _rng.randf_range(0.5, 1.0))
		r["cargo"][c] -= n
		if r["cargo"][c] <= 0:
			r["cargo"].erase(c)
		stolen.append("%d %s" % [n, Items.display_name(c)])
	if stolen.is_empty():
		return
	var near := sys_id == current_system or sys_id in neighbors(current_system)
	_post("Sea Peoples raiders hijacked the %s %s '%s' in %s - stole %s." % [EMPIRES[r["empire"]]["short"],
		EnemyTypes.get_type(r["type"])["name"].to_lower(), r["name"], systems[sys_id]["name"], ", ".join(stolen)],
		"news" if near else "quiet")


## A trader's ship in the current system was destroyed.
func trader_destroyed(id: String) -> void:
	traders.erase(id)


## The game is leaving the system: hand flown traders back to the simulation.
func release_live(id: String, pos: Vector2) -> void:
	var r: Dictionary = traders.get(id, {})
	if r.is_empty():
		return
	r["live"] = false
	if not r["legs"].is_empty():
		var leg: Dictionary = r["legs"][0]
		var a := Vector2(leg["from"][0], leg["from"][1])
		var b := Vector2(leg["to"][0], leg["to"][1])
		var len := maxf(a.distance_to(b), 1.0)
		r["t"] = clampf(1.0 - pos.distance_to(b) / len, 0.0, 0.99)


## Traders currently travelling inside a system (for spawning their ships).
func traders_in(sys_id: String) -> Array:
	var out := []
	for id in traders:
		var r: Dictionary = traders[id]
		if r["state"] == "travel" and r["system"] == sys_id and not r["legs"].is_empty():
			out.append(r)
	return out


func leg_position(r: Dictionary) -> Vector2:
	var leg: Dictionary = r["legs"][0]
	return Vector2(leg["from"][0], leg["from"][1]).lerp(Vector2(leg["to"][0], leg["to"][1]), clampf(r["t"], 0.0, 1.0))


func leg_target(r: Dictionary) -> Vector2:
	var leg: Dictionary = r["legs"][0]
	return Vector2(leg["to"][0], leg["to"][1])


# --- Diplomacy -----------------------------------------------------------------------------

func _diplomacy_tick() -> void:
	var a: String = MAJOR[_rng.randi() % MAJOR.size()]
	var b: String = MAJOR[(MAJOR.find(a) + 1 + _rng.randi() % (MAJOR.size() - 1)) % MAJOR.size()]
	var before := at_war(a, b)
	var v := relation(a, b) + _rng.randf_range(-28.0, 22.0)
	if before:
		v += 6.0   # wars tire out
	_set_relation(a, b, v)
	var now := at_war(a, b)
	if now and not before:
		_post("WAR: the %s has declared war on the %s!" % [empire_name(a), empire_name(b)], "danger")
	elif before and not now:
		_set_relation(a, b, maxf(v, -35.0))
		_post("PEACE: the %s and the %s have signed a peace treaty." % [empire_name(a), empire_name(b)], "good")
	# Wars move borders: a system next to the enemy may change hands.
	for x in MAJOR:
		for y in MAJOR:
			if x < y and at_war(x, y) and _rng.randf() < 0.35:
				_border_battle(x, y)
	_guests_tick()
	_recover_reputation((_diplo_last - time) / -60.0 if _diplo_last > 0.0 else 1.0)
	_diplo_last = time
	politics_changed.emit()


var _diplo_last := 0.0
## Runtime-added stations, to rebuild them on loading: [{system, empire, ang, dist, econ}].
var added_stations: Array = []


## Empires move in on each other's systems: an ally next door may be granted
## an outpost; an empire at war with the owner may set up a forward base (it
## undermines the system from inside - _control_cycle); an outpost of an
## empire no longer welcome (relations soured below alliance, at peace)
## goes its own way, independent.
func _guests_tick() -> void:
	# Outposts no longer welcome.
	for sid in stations:
		var st: Dictionary = stations[sid]
		var e := station_owner(sid)
		var o := owner_of(st["system"])
		if e != o and e in MAJOR and o != "pirates" and not at_war(e, o) and relation(e, o) < 20.0:
			st["empire"] = "independent"
			_post("%s: the %s station %s is on its own now - it has declared itself independent." % [systems[st["system"]]["name"], EMPIRES[e]["short"], st["name"]], "news")
	if _rng.randf() > 0.3:
		return
	var ids := systems.keys()
	var id: String = ids[_rng.randi() % ids.size()]
	var sys: Dictionary = systems[id]
	var o: String = sys["owner"]
	if id == HOME or o == "pirates" or not _room_for_guest(id):
		return
	for e in MAJOR:
		if e == o or not _borders(e, id) or guests_in(id).any(func(g): return station_owner(g) == e):
			continue
		var allied := relation(e, o) >= 40.0 and not at_war(e, o)
		if not (allied or at_war(e, o)):
			continue
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(3500.0, 8500.0)
		var econ := "trade_hub" if allied else "military"
		var st := _add_guest(sys, e, ang, dist, econ)
		if st.is_empty():
			return
		added_stations.append({"system": id, "empire": e, "ang": ang, "dist": dist, "econ": econ})
		for c in BASE_COMMODITIES:
			st["stock"][c] = 60.0 if c != "alien_alloy" else 3.0
		if allied:
			_post("%s: with the %s's leave, the %s has opened an outpost - %s." % [sys["name"], empire_name(o), empire_name(e), st["name"]], "news")
		else:
			_post("%s: the %s has set up a forward base - %s - to take the system from the %s." % [sys["name"], empire_name(e), st["name"], empire_name(o)], "danger")
		return


## A system changes hands: the old owner's stations there are captured by the
## new one (a forward base of the winner just becomes one of its own).
func _transfer(sys_id: String, from: String, to: String) -> void:
	for sid in system(sys_id).get("stations", []):
		if station_owner(sid) == from:
			stations[sid]["empire"] = to


func _border_battle(x: String, y: String) -> void:
	var attacker := x if _rng.randf() < 0.5 else y
	var defender := y if attacker == x else x
	var options := []
	for id in systems:
		if id == HOME or owner_of(id) != defender:
			continue
		for n in neighbors(id):
			if owner_of(n) == attacker:
				options.append(id)
				break
	if options.is_empty():
		return
	var target: String = options[_rng.randi() % options.size()]
	# Capitals hold out longer.
	if target in ["kyros", "nyx", "naxos"] and _rng.randf() < 0.75:
		_post("The %s assault on %s was repelled by the %s." % [EMPIRES[attacker]["short"], systems[target]["name"], empire_name(defender)], "news")
		return
	systems[target]["owner"] = attacker
	_transfer(target, defender, attacker)
	_post("%s has fallen: the %s captured it from the %s." % [systems[target]["name"], empire_name(attacker), empire_name(defender)], "danger")


## Systems drift in and out of states (boom, famine, outbreak, raids...).
func _states_tick() -> void:
	var ids := systems.keys()
	for i in 2:
		var id: String = ids[_rng.randi() % ids.size()]
		var sys: Dictionary = systems[id]
		if sys["state"] != "none":
			_post("%s: the %s is over." % [sys["name"], STATES[sys["state"]]["name"].to_lower()], "quiet")
			sys["state"] = "none"
			continue
		var options := ["boom", "bust", "famine", "outbreak", "civil_unrest", "pirate_raids", "expansion"]
		if sys["owner"] == "pirates":
			options = ["boom", "famine", "outbreak"]
		var st: String = options[_rng.randi() % options.size()]
		sys["state"] = st
		var near := id == current_system or id in neighbors(current_system)
		_post("%s %s: %s" % [sys["name"], STATES[st]["name"].to_upper(), STATES[st]["desc"]], "news" if near else "quiet")
	politics_changed.emit()


# --- Bounties ------------------------------------------------------------------------------

## The bounty the system's owner pays for a pirate ship with this hull and
## shields (before the Pirate Raids and reputation bonuses).
static func pirate_bounty(hull: float, shields: float) -> int:
	return roundi((hull + shields) * BOUNTY_PER_POINT + BOUNTY_BASE)


## The control cycle: systems weakened by enemy undermining may flip.
func _control_cycle() -> void:
	for id in systems:
		var sys: Dictionary = systems[id]
		var o: String = sys["owner"]
		if o == "pirates" or id == HOME:
			sys["undermine"] = {}
			continue
		# Empires undermine their war enemies' border systems - harder from a
		# forward base inside one.
		for n in neighbors(id):
			var no := owner_of(n)
			if no != "pirates" and no != o and at_war(no, o):
				sys["undermine"][no] = sys["undermine"].get(no, 0.0) + _rng.randf_range(4.0, 14.0)
		for g in guests_in(id):
			var ge := station_owner(g)
			if ge in MAJOR and at_war(ge, o):
				sys["undermine"][ge] = sys["undermine"].get(ge, 0.0) + _rng.randf_range(6.0, 12.0)
		var best := ""
		var best_v := 0.0
		for e in sys["undermine"]:
			if sys["undermine"][e] > best_v:
				best = e
				best_v = sys["undermine"][e]
		sys["control"] = clampf(sys["control"] + 8.0 - best_v, 0.0, 100.0)
		if sys["control"] <= 0.0 and best != "":
			sys["owner"] = best
			_transfer(id, o, best)
			sys["control"] = 35.0
			_post("POWER SHIFT: %s now answers to the %s (undermined from the %s)." % [sys["name"], empire_name(best), empire_name(o)], "danger")
		sys["undermine"] = {}
	politics_changed.emit()


func _post(text: String, kind: String) -> void:
	news.push_front({"t": time, "text": text, "kind": kind})
	if news.size() > 60:
		news.pop_back()
	if kind != "quiet":
		news_posted.emit(text, kind)


# --- Player trading -------------------------------------------------------------------------

func player_buy(station_id: String, item: String, qty: int, data: Node) -> int:
	var st: Dictionary = stations.get(station_id, {})
	if st.is_empty():
		return 0
	qty = mini(qty, int(st["stock"].get(item, 0.0)))
	qty = mini(qty, Inventory.room_for(data.items, item, Shipyard.cargo_capacity(data)))
	var bought := 0
	var spent := 0
	for i in qty:
		var p := buy_price(station_id, item)   # each unit moves the price
		if not data.spend(p):
			break
		st["stock"][item] -= 1.0
		_push_price(st, item, 1.0)
		data.add_item(item, 1)
		bought += 1
		spent += p
	change_reputation(station_owner(station_id), spent * REP_TRADE)   # (trading with them: they like you)
	cache_prices(station_id)
	return bought


func player_sell(station_id: String, item: String, qty: int, data: Node) -> int:
	var st: Dictionary = stations.get(station_id, {})
	if st.is_empty():
		return 0
	var earned := 0
	for i in qty:
		if not data.remove_item(item, 1):
			break
		var p := sell_price(station_id, item)
		earned += p
		_push_price(st, item, -1.0)
		st["stock"][item] = st["stock"].get(item, 0.0) + 1.0
	if earned > 0:
		data.add_credits(earned)
		change_reputation(station_owner(station_id), earned * REP_TRADE)
	cache_prices(station_id)
	return earned


## One unit you traded at `st`: +1 bought (its price rises), -1 sold (it
## falls) - harder on goods the station is short of.
func _push_price(st: Dictionary, item: String, dir: float) -> void:
	var ratio: float = st["stock"].get(item, 40.0) / (100.0 if item != "alien_alloy" else 10.0)
	var scarce := clampf(1.0 - ratio, 0.0, 1.0)
	if not st.has("impact"):
		st["impact"] = {}
	st["impact"][item] = float(st["impact"].get(item, 0.0)) + dir * PLAYER_IMPACT * (1.0 + IMPACT_SCARCE * scarce)


## Units of trade goods / loot in the player's hold.
## Slots taken in the hold (every item; Inventory).
func cargo_used(data: Node) -> int:
	return Inventory.slots_used(data.items)


# --- Fog of war ------------------------------------------------------------------------------

func fog(sys_id := "") -> FogOfWar:
	if sys_id == "":
		sys_id = current_system
	if not _fogs.has(sys_id):
		var n := int(FOG_EXTENT * 2.0 / FOG_CELL)
		var f := FogOfWar.new(n, n, Vector2(-FOG_EXTENT, -FOG_EXTENT), FOG_CELL)
		f.smooth = 6
		if _all_seen:
			f.data.fill(255)
		f.load_from(str(explored.get(sys_id, "")))
		_fogs[sys_id] = f
	return _fogs[sys_id]


## Your sensors sweep round `pos` in the current system.
func reveal(pos: Vector2, radius := SENSOR_RANGE) -> bool:
	return fog().reveal(pos, radius)


## Explored (shown on the system map) in the current system?
func explored_at(pos: Vector2) -> bool:
	return fog().explored(pos)


## The navigation beacon scanned: the system's report made (`report`, kept),
## its stations known (trade runs to them) - the fog stays. True if this visit
## gives a report (one a visit: report_issued).
func chart_system(sys_id := "", report := {}) -> bool:
	if sys_id == "":
		sys_id = current_system
	charted[sys_id] = true
	if not report.is_empty():
		reports[sys_id] = report
	for sid in system(sys_id).get("stations", []):
		see_station(str(sid))
	if int(report_issued.get(sys_id, -1)) == jumps:
		return false
	report_issued[sys_id] = jumps
	return true


func _explored_data() -> Dictionary:
	var out := explored.duplicate()
	for id in _fogs:
		out[id] = _fogs[id].save()
	return out


# --- Signal sources ----------------------------------------------------------------------

## The signal sources of a system (this one by default): this epoch's set,
## plus any you've located and not finished from before (at most 12 of those).
func signals_in(sys_id := "") -> Array:
	if sys_id == "":
		sys_id = current_system
	var ep := int(time / SignalSites.EPOCH)
	var rec: Dictionary = signals.get(sys_id, {})
	if rec.is_empty() or int(rec.get("epoch", -1)) != ep:
		var keep: Array = rec.get("list", []).filter(func(s): return s["located"] and not s["done"]).slice(0, 12)
		var ids := keep.map(func(s): return s["id"])
		rec = {"epoch": ep, "list": keep + SignalSites.generate(sys_id, ep).filter(func(s): return not s["id"] in ids)}
		signals[sys_id] = rec
	return rec["list"]


# --- Saving ----------------------------------------------------------------------------------

func get_save_data() -> Dictionary:
	var st := {}
	var impact := {}
	for sid in stations:
		st[sid] = stations[sid]["stock"]
		if not stations[sid].get("impact", {}).is_empty():
			impact[sid] = stations[sid]["impact"]
	var owners := {}
	var states := {}
	for id in systems:
		owners[id] = systems[id]["owner"]
		states[id] = systems[id]["state"]
	# The traders' countdowns to the millisecond: one just under zero (waiting
	# its turn to leave - one a frame) came back from the JSON a hair off.
	var tr := traders.duplicate(true)
	for id in tr:
		if tr[id].has("wait"):
			tr[id]["wait"] = snappedf(float(tr[id]["wait"]), 0.001)
	return {"time": time, "system": current_system, "relations": relations, "reputation": reputation,
		"stocks": st, "impact": impact, "owners": owners, "states": states, "traders": tr, "news": news.slice(0, 30),
		"next_id": _next_id, "route": route, "added_stations": added_stations,
		"destroyed": destroyed_stations, "visited": visited.keys(), "seen": seen.keys(),
		"health": stations.keys().filter(func(k): return float(stations[k].get("health", 100.0)) < 100.0).map(func(k): return [k, stations[k]["health"]]),
		"fleets": Fleets.get_save_data(),
		"station_owners": stations.keys().map(func(k): return [k, station_owner(k)]), "rocks": rocks, "explored": _explored_data(), "charted": charted.keys(), "reports": reports, "jumps": jumps, "report_issued": report_issued, "signals": signals, "control": systems.keys().map(func(k): return [k, systems[k]["control"]])}


func load_save_data(d: Dictionary) -> void:
	new_game(false)
	news = []
	if d.is_empty():
		return
	time = d.get("time", 0.0)
	current_system = d.get("system", HOME)
	# Stations set up since the start (outposts, forward bases), in order.
	for a in d.get("added_stations", []):
		var st := _add_guest(systems[a["system"]], a["empire"], float(a["ang"]), float(a["dist"]), a["econ"], true) if systems.has(a["system"]) else {}
		if not st.is_empty():
			added_stations.append(a)
	for k in d.get("relations", {}):
		var parts: PackedStringArray = k.split("|")
		_set_relation(parts[0], parts[1], d["relations"][k])
	reputation.merge(d.get("reputation", {}), true)
	rocks = d.get("rocks", {})
	explored = d.get("explored", {}).duplicate()
	_fogs = {}
	_all_seen = not d.has("explored")
	charted = {}
	for sid in d.get("charted", []):
		charted[str(sid)] = true
	reports = d.get("reports", {}).duplicate(true)
	jumps = int(d.get("jumps", 0))
	report_issued = d.get("report_issued", {}).duplicate()
	signals = d.get("signals", {}).duplicate(true)
	for sid in d.get("stocks", {}):
		if stations.has(sid):
			for c in d["stocks"][sid]:
				stations[sid]["stock"][c] = float(d["stocks"][sid][c])
	for sid in d.get("impact", {}):
		if stations.has(sid):
			for c in d["impact"][sid]:
				stations[sid]["impact"][c] = float(d["impact"][sid][c])
	for id in d.get("owners", {}):
		if systems.has(id):
			systems[id]["owner"] = d["owners"][id]
	for id in d.get("states", {}):
		if systems.has(id):
			systems[id]["state"] = d["states"][id]
	if d.has("traders"):
		traders = {}
		for id in d["traders"]:
			var r: Dictionary = d["traders"][id]
			r["live"] = false
			# Older saves: retired ship classes / role names.
			r["role"] = OLD_ROLES.get(r.get("role", "trader"), r.get("role", "trader"))
			if not EnemyTypes.has_type(r["type"]):
				r["type"] = ShipDesigns.pick(r["empire"], [r["role"]])
			for c in r["cargo"].keys():
				r["cargo"][c] = int(r["cargo"][c])
			r["capacity"] = int(r.get("capacity", 15))
			r["credits"] = int(r.get("credits", 0))
			traders[id] = r
	news = d.get("news", [])
	_next_id = int(d.get("next_id", 1000))
	route = d.get("route", [])
	for pair in d.get("station_owners", []):
		if stations.has(pair[0]):
			stations[pair[0]]["empire"] = str(pair[1])
	for pair in d.get("health", []):
		if stations.has(pair[0]):
			stations[pair[0]]["health"] = float(pair[1])
	for sid in d.get("destroyed", []):
		if stations.has(sid):
			var sys_id: String = stations[sid]["system"]
			systems[sys_id]["stations"].erase(sid)
			stations.erase(sid)
			_rehome_traders(sid, sys_id)   # (its traders moved on, as when it fell)
		destroyed_stations.append(sid)
	# (and any trader still pointing at a station that's gone - saves made
	# before this was done)
	for id in traders.keys():
		var r: Dictionary = traders[id]
		for k in ["station", "dest"]:
			if str(r.get(k, "")) != "" and not stations.has(str(r[k])):
				_rehome_traders(str(r[k]), str(r.get("system", "")))
	for sid in d.get("visited", []):
		visited[sid] = true
	for sid in d.get("seen", []):
		seen[sid] = true
	knowledge += 1
	Fleets.load_save_data(d.get("fleets", {}))
	_plan_goods()
	price_cache = {}   # (and the averages with it: only this galaxy's stations)
	sell_sum = {}
	sell_n = {}
	for sid in stations:
		_stock_goods(stations[sid])   # (saves from before the 126 goods: added)
		cache_prices(sid)   # (the loaded stocks' prices)
	for pair in d.get("control", []):
		if systems.has(pair[0]):
			systems[pair[0]]["control"] = float(pair[1])
	active = true
