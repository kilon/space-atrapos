class_name Planets
## Planets you can see from space (the background Parallax2D layer) and the
## surfaces you can land on. `template` / `variant` / `look`: the planet's
## appearance from space (PlanetGen; `look` overrides its parameters).
##
## Terrain: ordered list of [name, colour, walkable, kind]; noise height picks
## the index, from low to high. `kind` picks the ground shader's detail pattern
## and the vegetation (see GROUND_KINDS). Each planet has a Minoan palace, a Minoan village
## and scenery. `water`: the one body of water on the surface - "coast",
## "lake", "river" or "none" (default: picked by the seed; SurfaceTerrain);
## `rock_color`: its crags' stone (default pale limestone).

const PLANETS := {
	"thalassa": {
		"name": "Amnissos", "template": "ocean", "variant": 0, "landable": true, "seed": 101,
		"desc": "An ocean world of shallow seas, beaches and green islands.",
		"terrain": [
			["Deep sea", Color(0.07, 0.2, 0.42), false, "water"],
			["Shallows", Color(0.13, 0.42, 0.58), false, "water"],
			["Beach", Color(0.86, 0.77, 0.53), true, "sand"],
			["Grassland", Color(0.52, 0.62, 0.28), true, "grass"],
			["Forest", Color(0.3, 0.45, 0.22), true, "forest"],
		],
		"thresholds": [-0.25, -0.1, -0.02, 0.3],
		"water": "coast",
		"tiles": "fo",   # the forest terrain tile set (TerrainTiles)
		"prop": "tree", "prop_color": Color(0.25, 0.65, 0.4),
		"building_color": Color(0.85, 0.82, 0.7), "light": Color(0.4, 0.95, 1.0),
	},
	"selene": {
		"name": "Kamares", "template": "barren", "variant": 0,
		"look": {"land_low": Color(0.26, 0.26, 0.28), "land_mid": Color(0.44, 0.44, 0.46), "land_high": Color(0.6, 0.6, 0.61),
			"land_peak": Color(0.78, 0.78, 0.79), "biome": 0.0, "atmosphere": Color(0.6, 0.6, 0.66), "tilt": 0.2}, "landable": true, "seed": 202,
		"desc": "Amnissos's small frozen moon: snowfields, ice crystals and the ruins of an old outpost.",
		"terrain": [
			["Crater floor", Color(0.27, 0.27, 0.3), true, "crater"],
			["Dark regolith", Color(0.4, 0.4, 0.43), true, "regolith"],
			["Regolith", Color(0.55, 0.55, 0.57), true, "regolith"],
			["Bright highland", Color(0.7, 0.7, 0.71), true, "regolith"],
		],
		"thresholds": [-0.3, -0.05, 0.25],
		"rock_color": Color(0.66, 0.66, 0.68),
		"tiles": "ic",   # the ice terrain tile set (TerrainTiles) - a frozen moon
		"prop": "rock", "prop_color": Color(0.5, 0.5, 0.53),
		"building_color": Color(0.6, 0.62, 0.7), "light": Color(0.75, 0.6, 1.0),
	},
	"krystallos": {
		"name": "Ida", "template": "glacier", "variant": 0, "landable": true, "seed": 303,
		"desc": "A frozen world of snowfields, blue ice and deep crevasses.",
		"terrain": [
			["Crevasse", Color(0.12, 0.2, 0.38), false, "crevasse"],
			["Blue ice", Color(0.55, 0.75, 0.9), true, "ice"],
			["Packed snow", Color(0.82, 0.89, 0.96), true, "snow"],
			["Fresh snow", Color(0.95, 0.97, 1.0), true, "snow"],
		],
		"thresholds": [-0.3, -0.05, 0.25],
		"water": "river", "rock_color": Color(0.62, 0.7, 0.8),
		"tiles": "ic",   # the ice terrain tile set (TerrainTiles)
		"prop": "crystal", "prop_color": Color(0.55, 0.9, 1.0),
		"building_color": Color(0.75, 0.85, 0.95), "light": Color(1.0, 0.75, 0.4),
	},
	# The volcanic planet (2026-11-10): Venus-like - basalt, ash and sulphur under
	# an orange haze, magma for water. Named after Akrotiri, the Minoan town on
	# Thera buried by the great eruption.
	"akrotiri": {
		"name": "Akrotiri", "template": "inferno", "variant": 0, "landable": true, "seed": 505,
		"desc": "A scorched volcanic world under an orange haze: basalt and ash plains, sulphur flats and rivers of magma.",
		"terrain": [
			["Magma", Color(0.95, 0.35, 0.05), false, "crevasse"],
			["Ash fields", Color(0.5, 0.46, 0.42), true, "sand"],
			["Basalt", Color(0.25, 0.22, 0.26), true, "regolith"],
			["Sulphur flats", Color(0.85, 0.72, 0.2), true, "crater"],
		],
		"thresholds": [-0.3, -0.05, 0.3],
		"water": "river", "rock_color": Color(0.3, 0.26, 0.28),
		"tiles": "vo",   # the volcanic terrain tile set (TerrainTiles): magma for water
		"villages": false, "industry": false,   # no buildings at all: only the wilds (and pirates)
		"prop": "boulder", "prop_color": Color(0.3, 0.26, 0.28),
		"building_color": Color(0.7, 0.62, 0.55), "light": Color(1.0, 0.55, 0.2),
	},
	"kronos": {
		"name": "Dikte", "template": "ringed_giant", "variant": 0, "landable": true, "seed": 404,
		"desc": "A banded gas giant. No ground - only refinery platforms hovering in its upper clouds, linked by bridges.",
		"terrain": [
			["Open sky", Color(0.55, 0.32, 0.14), false, "sky"],
			["Deck", Color(0.46, 0.5, 0.56), true, "deck"],
			["Solar decks", Color(0.3, 0.36, 0.6), true, "solar"],
			["Upper works", Color(0.62, 0.66, 0.72), true, "grating"],
		],
		"thresholds": [-0.2, 0.3, 0.5],
		"water": "islands",   # platforms in the sky, bridges between them (SurfaceTerrain)
		"tiles": "gg",        # the gas giants' platform tile set (TerrainTiles): open sky for water
		"villages": false,    # no Minoan villages: industrial sites instead (PlanetSurface.INDUSTRY)
		"sky_color": Color(0.85, 0.55, 0.3),
		"prop": "boulder", "prop_color": Color(0.5, 0.52, 0.56), "rock_color": Color(0.45, 0.48, 0.52),
		"building_color": Color(0.6, 0.64, 0.7), "light": Color(0.45, 0.9, 1.0),
	},
}

## Ground kinds understood by shaders/ground.gdshader (index = shader id).
const GROUND_KINDS := ["water", "sand", "grass", "forest", "regolith", "crater", "ice", "snow", "crevasse", "sky", "deck", "solar", "grating"]



## Things Minoan citizens say (Minoan words, then the translation). The
## libation formula a-sa-sa-ra-me and ku-ro ("total") are real Linear A.
const DEFAULT_NPC_LINES := [
	["A-sa-sa-ra-me!", "Praise to the Lady! (the Linear A libation formula)"],
	["Ku-ro, ku-ro.", "Everything is counted. The palace stores are full."],
	["Ta-na-ra-te u-ti-nu.", "Welcome, sky-traveller. Walk in peace."],
	["Ja-sa-sa-ra-me...", "May the Lady guard your ship."],
	["Ka-pa da-ku-se-ne.", "The bull dancers leap at the next festival - come and watch."],
	["I-da-ma-te!", "By the mountain Ida! Your ship is loud."],
	["Pa-i-to, ku-do-ni-ja.", "Phaistos and Kydonia send their greetings."],
	["Su-ki-ri-ta.", "The warehouses trade oil, wine and star-metal."],
	["A-ka-ru da-ku-se.", "Our spirals mark the paths of the sea and the stars."],
	["Hmm-hm.", "(It rumbles a low, friendly greeting through its beak.)"],
]

## A named planet's appearance (PlanetGen parameters).
static func spec(id: String) -> Dictionary:
	var p: Dictionary = get_planet(id)
	return PlanetGen.generate(p.get("template", "barren"), int(p.get("variant", 0)), p.get("look", {}))


## A planet node `size` px across (see PlanetGen.make).
static func make_planet(p: Dictionary, size: float, radius := PlanetGen.DISK, cached := false) -> Control:
	return PlanetGen.make(p, size, radius, cached)


## The planet types of generated systems (Galaxy._generate_planets): each a
## named planet's surface (`base`: its terrain, tiles, fauna, environment) with
## its own name, seed and look from space (one of `templates`). Moons are
## Kamares's kind: grey regolith and craters.
const TYPES := {
	"ocean": {"base": "thalassa", "templates": ["ocean"], "label": "ocean world",
		"desc": "An ocean world of shallow seas, beaches and green islands."},
	"ice": {"base": "krystallos", "templates": ["glacier"], "label": "ice world",
		"desc": "A frozen world of snowfields, blue ice and deep crevasses."},
	"volcanic": {"base": "akrotiri", "templates": ["inferno"], "label": "volcanic world",
		"desc": "A scorched volcanic world: basalt and ash plains, sulphur flats and rivers of magma."},
	"gas_giant": {"base": "kronos", "templates": ["ringed_giant", "storm_giant"], "label": "gas giant",
		"desc": "A banded gas giant. No ground - only refinery platforms hovering in its upper clouds, linked by bridges."},
	"moon": {"base": "selene", "templates": ["barren"], "label": "moon",
		"desc": "A small grey moon of %s: regolith, rock and craters."},
}

## A planet you can land on: a named one (PLANETS) or one of a generated
## system's (Galaxy.planets: "<system>_p<n>", moons "..m<k>") - its type's
## surface under its own name and seed. {} if there's no such planet.
static func get_planet(id: String) -> Dictionary:
	if PLANETS.has(id):
		return PLANETS[id]
	var rec: Dictionary = Galaxy.planet_record(id)
	if rec.is_empty():
		return {}
	var t: Dictionary = TYPES[rec["type"]]
	var p: Dictionary = PLANETS[t["base"]].duplicate(true)
	p.erase("look")
	var desc := str(t["desc"])
	if rec["type"] == "moon":
		desc = desc % str(Galaxy.planet_record(rec["moon_of"]).get("name", "its planet"))
	p.merge({"name": rec["name"], "template": rec["template"], "variant": rec["variant"], "seed": int(rec["seed"]),
		"desc": desc, "landable": true, "type": rec["type"]}, true)
	return p


## True if `id` is a planet you can land on.
static func exists(id: String) -> bool:
	return not get_planet(id).is_empty()


## What a planet's environment does to you on foot, by its tile set:
##   regen   how fast your health comes back (volcanic: the heat - half as fast)
##   speed   how fast you walk (ice: slippery footing - 20% slower)
## A planet's own "environment" entry overrides its set's.
const ENVIRONMENT := {
	"vo": {"regen": 0.5, "speed": 1.0, "note": "The heat: your health comes back half as fast."},
	"ic": {"regen": 1.0, "speed": 0.8, "note": "Slippery ice: you walk 20% slower."},
}


static func environment(id: String) -> Dictionary:
	var p := get_planet(id)
	var e: Dictionary = {"regen": 1.0, "speed": 1.0, "note": ""}
	e.merge(ENVIRONMENT.get(str(p.get("tiles", "")), {}), true)
	e.merge(p.get("environment", {}), true)
	return e


# --- Editable interactions (data/interactions.json) -------------------------------

const INTERACTIONS_FILE := "res://data/interactions.json"
static var NPC_LINES: Array = []


static func _static_init() -> void:
	reload()


static func reload() -> void:
	var d := DataFiles.read(INTERACTIONS_FILE)
	NPC_LINES = d.get("npc_lines", DEFAULT_NPC_LINES.duplicate(true))


static func save_interactions() -> String:
	return DataFiles.write(INTERACTIONS_FILE, {
		"_help": "Things Minoan citizens say ([Minoan words, translation]). Edit here or in-game: right-click > Developer Mode.",
		"npc_lines": NPC_LINES,
	})
