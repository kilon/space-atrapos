class_name CosmosFlora
extends RefCounted
## A planet's plants in the 3D game: species designed from the planet's seed
## and type, each its own small mesh built here, and the rules for where it
## grows. The green (ocean) worlds read as Greece: olive trees with gnarled,
## twisted trunks and silver-green crowns, dark columns of cypress, umbrella
## stone pines and leaning Aleppo pines, plane trees by the water, holm oaks,
## carobs and figs, firs on the heights, palms on warm shores, a dead snag
## now and then; the maquis (lentisk and kermes oak mounds, broom, oleander by
## the shore, rockrose) and the phrygana's grey-green cushions of thyme and
## sage; short green turf in the lowlands, golden dry grass on the hillsides,
## tufts and reeds; poppies, daisies, asphodels, anemones and thistles in the
## meadows. The other worlds keep their alien flora (glowing, crystalline,
## fungal trees, crystals, fungi, cacti).
##
## Meshes: trees are real branching geometry - recursive trunk and limb tubes
## (tapered, lobed and twisted where gnarled, bark streaked or mottled) with
## foliage clumps clustered at the limbs' tips, shaded as one crown (their
## normals bent toward the crown's, darker inside and below). One surface a
## species: wood and leaves in one mesh (vertex colours; UV2.x 1 marks leaves -
## translucent, fluttering; UV2.y > 0 a draw distance the plant shrinks away
## at - grass and flowers fade out, not pop). Each species has a far mesh too
## (the same tree: no twigs, coarser clumps); the trees and shrubs a whole chain
## of levels of detail down to an impostor, drawn to the horizon (FloraLods).
##
## Placement (scatter - the grass and flowers on the finest patches; the trees
## and shrubs FloraLods.own, the same rules, carried down the quadtree - on
## CosmosPlanet's patch workers): per species a seeded
## candidate count from its density, each kept by chance: woods and open land
## from a low-frequency noise (forests and groves, meadows and clearings, lone
## trees in the open), each species its own territories (the same species near
## each other), its heights (shore, lowland, hills, mountains), slopes, the
## green lowlands for the turf. Sizes skewed to the middle with saplings and
## old giants, each plant turned, tilted and stretched a little its own way.
## Thread-safe: designs are plain data (mesh arrays) and a FastNoiseLite only read.
##   var species := CosmosFlora.design(shape, seed, type)   # [{kind, design, arrays, far, ...}]

const KINDS_BY_TYPE := {
	"ocean": ["tree", "bush", "grass", "flower"],
	"ice": ["spire", "crystal", "grass"],
	"volcanic": ["crystal", "fungus", "cactus"],
	"moon": ["crystal"],
	"rocky": ["cactus", "fungus", "grass"],
}

## Each world type's designs: [always] + [a few of these].
const GREEK_TREES := ["stone_pine", "aleppo_pine", "plane", "oak", "carob", "fig", "fir", "palm"]
const GREEK_BUSHES := ["broom", "oleander", "rockrose"]
const GREEK_FLOWERS := ["poppy", "daisy", "asphodel", "anemone", "thistle"]
const ALIEN := {
	"ice": [["fir", "crystaltree", "crystal", "tuft", "phrygana"], ["snag", "glowtree"], 1],
	"volcanic": [["crystaltree", "snag", "crystal", "fungus", "cactus"], ["fungustree", "glowtree"], 1],
	"moon": [["crystal", "crystaltree"], [], 0],
	"rocky": [["glowtree", "fungustree", "cactus", "fungus", "tuft"], ["snag", "crystaltree", "phrygana"], 2],
}
const KIND_OF := {
	"olive": "tree", "plane": "tree", "oak": "tree", "carob": "tree", "fig": "tree", "aleppo_pine": "tree",
	"stone_pine": "tree", "snag": "tree", "palm": "tree", "glowtree": "tree", "fungustree": "tree", "crystaltree": "tree",
	"cypress": "spire", "fir": "spire",
	"maquis": "bush", "phrygana": "bush", "broom": "bush", "oleander": "bush", "rockrose": "bush",
	"turf": "grass", "golden": "grass", "tuft": "grass", "reeds": "grass",
	"poppy": "flower", "daisy": "flower", "asphodel": "flower", "anemone": "flower", "thistle": "flower",
	"crystal": "crystal", "fungus": "fungus", "cactus": "cactus",
}
const GRASS_FADE := 44.0     # m: grass shrinks away by here (and isn't drawn past it)
const FLOWER_FADE := 36.0


## The species of a planet (its PlanetShape, seed and type).
## `stop` [true]: given up part way (its world gone - CosmosPlanet's exit waits for this).
static func design(shape: PlanetShape, seed: int, type: String, stop: Array = []) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 7
	var L := shape.look
	var designs: Array = _designs_of(rng, type)
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = seed * 13 + 5
	noise.frequency = 1.0
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 3
	var out: Array = []
	for i in designs.size():
		if not stop.is_empty() and stop[0]:
			return out
		var sp := _species(str(designs[i]), rng, L, type)
		sp["noise"] = noise
		sp["off"] = Vector3(rng.randf_range(-500, 500), rng.randf_range(-500, 500), rng.randf_range(-500, 500))
		out.append(sp)
	return out


static func _designs_of(rng: RandomNumberGenerator, type: String) -> Array:
	var out: Array = []
	if type == "ocean":
		out = ["olive", "cypress"]
		out.append_array(_pick(rng, GREEK_TREES, 4))
		out.append("snag")
		out.append_array(["maquis", "phrygana"])
		out.append_array(_pick(rng, GREEK_BUSHES, 2))
		out.append_array(["turf", "golden", "tuft", "reeds"])
		out.append_array(_pick(rng, GREEK_FLOWERS, 3))
		return out
	var A: Array = ALIEN.get(type, ALIEN["rocky"])
	out = (A[0] as Array).duplicate()
	out.append_array(_pick(rng, A[1], int(A[2])))
	return out


static func _pick(rng: RandomNumberGenerator, from: Array, n: int) -> Array:
	var pool := from.duplicate()
	var out: Array = []
	for i in mini(n, pool.size()):
		out.append(pool.pop_at(rng.randi() % pool.size()))
	return out


## Colours: Greece's own, a little of the planet's palette and its empire's tint.
static func _tint(c: Color, L: Dictionary, rng: RandomNumberGenerator, k := 0.2) -> Color:
	var leaf: Color = L.get("land_mid", c)
	var o := c.lerp(leaf, k * 0.4 * rng.randf())
	if L.has("flora"):   # (the empire's land: PlanetShape._empire_tint)
		o = o.lerp(L["flora"], float(L.get("flora_k", 0.0)) * 0.6)
	return o.lightened(rng.randf_range(-0.05, 0.06))


## One species: its mesh (and far mesh), where and how thick it grows, its sizes.
##   density: plants a 100 m2 where it grows best; size: its scale range (giants
##   and saplings beyond); band: its heights [lo, hi] (x the relief's amp);
##   wood: +1 in the woods, -1 in the open, 0 either; group: its territories' size (m);
##   green: 1 only on the green lowlands, -1 the drier hills; shore: by the sea only.
static func _species(dname: String, rng: RandomNumberGenerator, L: Dictionary, type: String) -> Dictionary:
	var kind: String = KIND_OF.get(dname, "tree")
	var sp := {"kind": kind, "design": dname, "color": Color(0.3, 0.45, 0.2), "density": 1.0, "min_h": 0.04, "max_h": 1.6,
		"max_slope": 0.4, "size": Vector2(0.8, 1.2), "solid": 0.0, "glow": 0.0, "range": 0.0, "wood": 0.0,
		"group": 200.0, "green": 0.0, "shore": false, "tilt": 0.05, "tall": 6.0, "lone": 0.05}
	var alien := type != "ocean"
	var hue := Color.from_hsv(rng.randf(), rng.randf_range(0.45, 0.8), rng.randf_range(0.5, 0.85))
	var seed := rng.randi()
	var mk := func(lod: int) -> Array: return _make(dname, seed, lod, sp, L)
	match dname:
		"olive":
			sp.merge({"color": _tint(Color(0.48, 0.5, 0.37), L, rng), "bark": Color(0.36, 0.33, 0.28), "density": 1.1,
				"size": Vector2(0.6, 1.25), "solid": 0.5, "wood": 0.6, "band": [0.03, 0.9], "group": 260.0, "tilt": 0.1, "tall": 5.0, "lone": 0.12}, true)
		"cypress":
			sp.merge({"color": _tint(Color(0.1, 0.17, 0.08), L, rng, 0.1), "bark": Color(0.33, 0.25, 0.2), "density": 0.7,
				"size": Vector2(0.55, 1.2), "solid": 0.4, "wood": 0.2, "band": [0.04, 1.3], "group": 120.0, "tilt": 0.03, "tall": 15.0, "lone": 0.15}, true)
		"stone_pine":
			sp.merge({"color": _tint(Color(0.2, 0.28, 0.15), L, rng), "bark": Color(0.42, 0.31, 0.23), "density": 0.7,
				"size": Vector2(0.6, 1.2), "solid": 0.45, "wood": 0.8, "band": [0.02, 0.8], "group": 220.0, "tilt": 0.08, "tall": 12.0}, true)
		"aleppo_pine":
			sp.merge({"color": _tint(Color(0.34, 0.4, 0.22), L, rng), "bark": Color(0.42, 0.38, 0.34), "density": 1.3,
				"size": Vector2(0.55, 1.2), "solid": 0.4, "wood": 1.0, "band": [0.02, 1.1], "group": 300.0, "tilt": 0.18, "tall": 10.0}, true)
		"plane":
			sp.merge({"color": _tint(Color(0.32, 0.43, 0.2), L, rng), "bark": Color(0.44, 0.42, 0.36), "density": 0.6,
				"size": Vector2(0.6, 1.25), "solid": 0.7, "wood": 0.3, "band": [0.02, 0.35], "group": 160.0, "tilt": 0.04, "tall": 17.0, "lowland": true}, true)
		"oak":
			sp.merge({"color": _tint(Color(0.2, 0.26, 0.15), L, rng), "bark": Color(0.3, 0.27, 0.23), "density": 1.0,
				"size": Vector2(0.6, 1.25), "solid": 0.55, "wood": 0.9, "band": [0.1, 1.4], "group": 240.0, "tall": 9.0}, true)
		"carob":
			sp.merge({"color": _tint(Color(0.17, 0.27, 0.12), L, rng), "bark": Color(0.4, 0.33, 0.27), "density": 0.8,
				"size": Vector2(0.65, 1.2), "solid": 0.5, "wood": 0.3, "band": [0.03, 0.6], "group": 180.0, "tall": 7.0, "lone": 0.12}, true)
		"fig":
			sp.merge({"color": _tint(Color(0.38, 0.5, 0.24), L, rng), "bark": Color(0.52, 0.5, 0.46), "density": 0.5,
				"size": Vector2(0.6, 1.2), "solid": 0.45, "wood": -0.2, "band": [0.03, 0.5], "group": 120.0, "tall": 5.0, "lone": 0.15}, true)
		"fir":
			sp.merge({"color": _tint(Color(0.11, 0.19, 0.14), L, rng, 0.1) if not alien else hue.darkened(0.3), "bark": Color(0.3, 0.24, 0.2),
				"density": 1.6, "size": Vector2(0.55, 1.2), "solid": 0.4, "wood": 1.0, "band": [0.9, 2.6] if not alien else [0.0, 1.8],
				"group": 260.0, "tall": 13.0, "max_slope": 0.5, "frost": alien}, true)
		"palm":
			sp.merge({"color": _tint(Color(0.3, 0.44, 0.16), L, rng), "bark": Color(0.45, 0.37, 0.27), "density": 1.4,
				"size": Vector2(0.65, 1.2), "solid": 0.3, "wood": 0.0, "band": [0.0, 0.16], "group": 140.0, "shore": true, "tilt": 0.1, "tall": 8.0}, true)
		"snag":
			sp.merge({"color": Color(0.5, 0.48, 0.44) if type != "volcanic" else Color(0.12, 0.1, 0.09), "density": 0.12,
				"size": Vector2(0.6, 1.2), "solid": 0.3, "wood": 0.0, "band": [0.0, 2.0], "group": 400.0, "tilt": 0.12, "tall": 7.0, "lone": 0.5}, true)
		"glowtree":
			sp.merge({"color": hue, "bark": hue.darkened(0.6), "density": 1.2, "size": Vector2(0.6, 1.3), "solid": 0.4, "wood": 0.6,
				"band": [-0.2, 1.6], "group": 220.0, "tall": 7.0, "glow": 0.8}, true)
		"fungustree":
			sp.merge({"color": hue, "bark": Color(0.82, 0.78, 0.7), "density": 0.9, "size": Vector2(0.5, 1.4), "solid": 0.35, "wood": 0.5,
				"band": [-0.3, 1.4], "group": 180.0, "tall": 8.0, "glow": 0.5 if rng.randf() < 0.5 else 0.0}, true)
		"crystaltree":
			var cc := Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), 0.95)
			if type == "volcanic":
				cc = L.get("lava_color", Color(1.0, 0.4, 0.1))
			sp.merge({"color": cc, "density": 0.7, "size": Vector2(0.5, 1.4), "solid": 0.35, "wood": 0.3, "band": [-0.3, 2.0],
				"group": 200.0, "tall": 6.0, "glow": 1.0, "max_slope": 0.6}, true)
		"maquis":
			sp.merge({"color": _tint(Color(0.2, 0.27, 0.15), L, rng), "density": 3.0, "size": Vector2(0.5, 1.4),
				"wood": 0.0, "band": [0.03, 1.3], "group": 90.0, "range": 160.0, "tall": 1.6, "lone": 0.2}, true)
		"phrygana":
			sp.merge({"color": _tint(Color(0.42, 0.47, 0.36), L, rng, 0.1), "density": 6.0, "size": Vector2(0.6, 1.4), "wood": -1.0,
				"band": [0.15, 2.2] if not alien else [-0.2, 2.0], "group": 70.0, "range": 75.0, "green": -1.0 if not alien else 0.0,
				"max_slope": 0.55, "lone": 0.15, "flecks": Color(0.62, 0.42, 0.72) if rng.randf() < 0.6 else Color(0.92, 0.9, 0.85)}, true)
		"broom":
			sp.merge({"color": _tint(Color(0.26, 0.38, 0.14), L, rng), "flower": Color(0.98, 0.82, 0.12), "density": 1.6,
				"size": Vector2(0.6, 1.3), "wood": -0.5, "band": [0.1, 1.2], "group": 80.0, "range": 90.0, "lone": 0.1}, true)
		"oleander":
			sp.merge({"color": _tint(Color(0.2, 0.32, 0.14), L, rng), "flower": [Color(0.95, 0.45, 0.62), Color(0.98, 0.92, 0.94), Color(0.88, 0.3, 0.42)][rng.randi() % 3],
				"density": 3.0, "size": Vector2(0.6, 1.3), "band": [0.0, 0.14], "shore": true, "group": 60.0, "range": 140.0, "tall": 2.4}, true)
		"rockrose":
			sp.merge({"color": _tint(Color(0.34, 0.42, 0.28), L, rng), "flower": Color(0.92, 0.55, 0.75) if rng.randf() < 0.6 else Color(0.97, 0.96, 0.92),
				"density": 3.0, "size": Vector2(0.6, 1.3), "wood": -0.6, "band": [0.08, 1.4], "group": 60.0, "range": 70.0, "lone": 0.1}, true)
		"turf":
			sp.merge({"color": _tint(Color(0.32, 0.45, 0.19), L, rng, 0.35), "density": 80.0, "size": Vector2(0.7, 1.3), "wood": -0.6,
				"band": [0.05, 0.75], "green": 1.0, "group": 90.0, "range": GRASS_FADE + 14.0, "max_slope": 0.5, "lone": 0.35}, true)
		"golden":
			sp.merge({"color": _tint(Color(0.74, 0.62, 0.36), L, rng, 0.1), "density": 24.0, "size": Vector2(0.7, 1.35), "wood": -0.7,
				"band": [0.25, 1.8], "green": -1.0, "group": 110.0, "range": GRASS_FADE + 14.0, "max_slope": 0.55, "lone": 0.3}, true)
		"tuft":
			sp.merge({"color": _tint(Color(0.38, 0.46, 0.26), L, rng, 0.4) if not alien else hue.lerp(L.get("land_mid", hue), 0.5),
				"density": 5.0, "size": Vector2(0.6, 1.4), "wood": -0.3, "band": [0.04, 2.0] if not alien else [-0.3, 1.6],
				"group": 50.0, "range": GRASS_FADE + 14.0, "max_slope": 0.6, "lone": 0.3}, true)
		"reeds":
			sp.merge({"color": _tint(Color(0.42, 0.5, 0.24), L, rng, 0.1), "density": 9.0, "size": Vector2(0.7, 1.3), "band": [0.0, 0.08],
				"shore": true, "group": 50.0, "range": 90.0, "max_slope": 0.3, "tilt": 0.08}, true)
		"poppy":
			sp.merge({"color": Color(0.85, 0.08, 0.05), "stem": Color(0.3, 0.44, 0.18), "density": 7.0, "wood": -1.0, "band": [0.05, 0.9], "green": 0.5,
				"group": 45.0, "range": FLOWER_FADE + 10.0, "lone": 0.05}, true)
		"daisy":
			sp.merge({"color": Color(0.97, 0.96, 0.9), "stem": Color(0.3, 0.44, 0.18), "density": 8.0, "wood": -1.0, "band": [0.05, 0.9], "green": 0.6,
				"group": 40.0, "range": FLOWER_FADE + 10.0, "lone": 0.05}, true)
		"asphodel":
			sp.merge({"color": Color(0.95, 0.88, 0.86), "stem": Color(0.34, 0.42, 0.2), "density": 3.5, "wood": -1.0, "band": [0.08, 1.4],
				"group": 60.0, "range": FLOWER_FADE + 10.0, "lone": 0.08}, true)
		"anemone":
			sp.merge({"color": [Color(0.75, 0.08, 0.12), Color(0.45, 0.2, 0.62), Color(0.92, 0.9, 0.95)][rng.randi() % 3], "stem": Color(0.3, 0.44, 0.18),
				"density": 5.0, "wood": -0.6, "band": [0.05, 1.0], "group": 40.0, "range": FLOWER_FADE + 10.0, "lone": 0.05}, true)
		"thistle":
			sp.merge({"color": Color(0.62, 0.3, 0.68), "stem": Color(0.5, 0.56, 0.44), "density": 2.5, "wood": -1.0, "band": [0.15, 1.6], "green": -0.5,
				"group": 50.0, "range": FLOWER_FADE + 10.0, "lone": 0.1}, true)
		"crystal":
			var cc := Color.from_hsv(rng.randf(), rng.randf_range(0.5, 0.9), 0.95)
			if type == "volcanic":
				cc = L.get("lava_color", Color(1.0, 0.4, 0.1))
			sp.merge({"color": cc, "density": 0.8, "size": Vector2(0.5, 2.0), "glow": 1.6, "band": [-0.3, 2.5], "max_slope": 0.7,
				"solid": 0.3, "wood": 0.0, "group": 150.0, "tall": 1.5, "lone": 0.3}, true)
		"fungus":
			sp.merge({"color": Color.from_hsv(rng.randf(), 0.6, 0.85), "stem": Color(0.85, 0.8, 0.7), "density": 2.0, "size": Vector2(0.6, 2.2),
				"glow": 0.6 if rng.randf() < 0.5 else 0.0, "band": [-0.3, 1.6], "group": 90.0, "range": 100.0, "wood": 0.3, "lone": 0.15}, true)
		"cactus":
			sp.merge({"color": hue.lerp(L.get("land_mid", hue), 0.5).darkened(0.15), "density": 0.9, "size": Vector2(0.6, 1.5), "solid": 0.35,
				"band": [-0.3, 1.6], "group": 150.0, "wood": -0.4, "tall": 3.0, "lone": 0.2}, true)
	var band: Array = sp.get("band", [0.04, 1.6])
	sp["min_h"] = float(band[0])
	sp["max_h"] = float(band[1])
	sp["arrays"] = mk.call(1)
	sp["far"] = mk.call(2) if float(sp["solid"]) > 0.0 else sp["arrays"]
	if LEAVES.has(dname) or dname in ["cypress", "fir"]:   # (up close: every branch and leaf)
		sp["near"] = mk.call(0)
		sp["cards"] = true   # (leaf cards: drawn with leaf_flora.gdshader, which cuts them)
	if FloraLods.is_stand(sp):   # (the trees, shrubs and the like: their chain of meshes down to the impostor - FloraLods)
		FloraLods.chain(sp)
	return sp


static func _make(dname: String, seed: int, lod: int, sp: Dictionary, L: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := M.new()
	m.lod = lod
	m.far = lod == 2
	var c: Color = sp["color"]
	match dname:
		"olive", "plane", "oak", "carob", "fig", "aleppo_pine", "stone_pine", "snag", "glowtree":
			_broadleaf(m, rng, dname, sp)
		"cypress":
			_cypress(m, rng, c, sp["bark"])
		"fir":
			_fir(m, rng, c, sp["bark"], bool(sp.get("frost", false)))
		"palm":
			_palm(m, rng, c, sp["bark"])
		"fungustree":
			_fungus_tree(m, rng, c, sp["bark"], float(sp["glow"]))
		"crystaltree":
			_crystal_tree(m, rng, c)
		"maquis":
			_mound(m, rng, c, 3, 6, 1.0, 0.8, 0.0, Color())
		"phrygana":
			_mound(m, rng, c, 3, 5, 0.34, 0.85, 0.3, sp["flecks"])
		"rockrose":
			_mound(m, rng, c, 3, 4, 0.4, 0.85, 0.22, sp["flower"])
		"broom":
			_broom(m, rng, c, sp["flower"])
		"oleander":
			_oleander(m, rng, c, sp["flower"])
		"turf":
			_grass_clump(m, rng, c, 56, 0.8, Vector2(0.14, 0.4), 0.3, false)
		"golden":
			_grass_clump(m, rng, c, 40, 0.6, Vector2(0.4, 0.95), 0.35, true)
		"tuft":
			_grass_clump(m, rng, c, 26, 0.18, Vector2(0.3, 0.65), 0.55, false)
		"reeds":
			_reeds(m, rng, c)
		"poppy", "anemone":
			_cup_flowers(m, rng, c, sp["stem"], 5 if dname == "poppy" else 6, dname == "anemone")
		"daisy":
			_daisies(m, rng, c, sp["stem"])
		"asphodel":
			_asphodel(m, rng, c, sp["stem"])
		"thistle":
			_thistle(m, rng, c, sp["stem"])
		"crystal":
			return _crystal(rng, c)
		"fungus":
			return _fungus(rng, c, sp["stem"], float(sp["glow"]))
		"cactus":
			return _cactus(rng, c)
	return m.arrays()


# --- The mesh builder --------------------------------------------------------------

## Packed arrays (indexed), smooth normals set here. UV.x the glow (> 0.9: rigid),
## UV.y how far the vertex sways; UV2.x 1 on leaves, UV2.y the fade distance.
class M:
	extends RefCounted
	var v := PackedVector3Array()
	var nr := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var ix := PackedInt32Array()
	var far := false
	var lod := 1        # 0 near: twigs and leaves; 1 the crown as clumps; 2 far: no twigs, coarse clumps
	var leaf_shape := ""   # (near: the clumps' leaves - LEAVES)
	var bark := Color(0.35, 0.3, 0.25)
	var silver := false # (leaves pale beneath: olive)
	var sway := 1.0     # (UV.y = height x this)
	var leaf := 0.0
	var fade := 0.0
	var glow := 0.0

	func add(p: Vector3, n: Vector3, col: Color) -> int:
		v.append(p)
		nr.append(n)
		c.append(col)
		uv.append(Vector2(glow, maxf(p.y, 0.0) * sway))
		uv2.append(Vector2(leaf, fade))
		return v.size() - 1

	## A triangle wound to face its vertices' normals (Godot's front faces wind clockwise).
	func tri(a: int, b: int, d: int) -> void:
		var out := nr[a] + nr[b] + nr[d]
		if (v[d] - v[a]).cross(v[b] - v[a]).dot(out) >= 0.0:
			ix.append(a); ix.append(b); ix.append(d)
		else:
			ix.append(a); ix.append(d); ix.append(b)

	func quad(a: int, b: int, d: int, e: int) -> void:
		tri(a, b, d)
		tri(a, d, e)

	## A leaf card: a quad from `p` along `up` (`l` long, `w` wide across `side`)
	## the shader cuts into leaves of `type` (CARD_*) - UV2.x 3 + u (5 + u: pale
	## beneath), UV2.y -(1 + 2 type + v).
	func card(p: Vector3, side: Vector3, up: Vector3, w: float, l: float, n: Vector3, col: Color, type: int) -> void:
		var base := v.size()
		var ux := 5.0 if silver else 3.0
		for k in 4:
			var u := float(k == 1 or k == 2)
			var t := float(k >= 2)
			var pt := p + side * (u - 0.5) * w + up * t * l
			v.append(pt)
			nr.append(n)
			c.append(col * (0.8 + 0.25 * t))
			uv.append(Vector2(glow, maxf(pt.y, 0.0) * sway))
			uv2.append(Vector2(ux + u * 0.999, -(1.0 + 2.0 * type + t * 0.999)))
		quad(base, base + 1, base + 2, base + 3)

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = nr
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = ix
		return arr


static func _perp(ax: Vector3) -> Vector3:
	return ax.cross(Vector3.RIGHT if absf(ax.x) < 0.9 else Vector3.FORWARD).normalized()


static func _rdir(rng: RandomNumberGenerator) -> Vector3:
	return Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()


## A smooth tube along `pts` (radii `rs`), `sides` round: lobes (a gnarled
## trunk's ridges, twisting up it), bark streaks, mottled patches.
static func _tube(m: M, seed: int, pts: PackedVector3Array, rs: PackedFloat32Array, sides: int, col: Color,
		lobe := 0.0, twist := 0.0, mottle := 0.0, patch := Color()) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	var n := pts.size()
	if n < 2:
		return
	var streak := PackedFloat32Array()
	for s in sides:
		streak.append(r.randf_range(0.78, 1.12))
	var ph := r.randf() * TAU
	var p := _perp((pts[1] - pts[0]).normalized())
	var base := m.v.size()
	for i in n:
		var tan: Vector3 = (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		p = (p - tan * p.dot(tan)).normalized()
		var q := tan.cross(p)
		var tt := float(i) / (n - 1)
		for s in sides:
			var a := TAU * s / sides
			var dv := p * cos(a) + q * sin(a)
			var k := 1.0 + lobe * sin(3.0 * a + twist * tt + ph) + lobe * 0.5 * sin(5.0 * a - twist * tt * 1.3)
			var cc := col * (streak[s] * r.randf_range(0.92, 1.05))
			if mottle > 0.0 and r.randf() < mottle:
				cc = patch * r.randf_range(0.9, 1.08)
			cc.a = 1.0
			m.add(pts[i] + dv * rs[i] * k, dv, cc)
	for i in n - 1:
		for s in sides:
			var a := base + i * sides + s
			var b := base + i * sides + (s + 1) % sides
			m.quad(a, b, b + sides, a + sides)


## A limb (and its limbs, `depth` deep): a bending tube from `at` along `dir`;
## its tips (where the leaves go) appended to `tips` as [point, direction, length].
static func _limb(m: M, rng: RandomNumberGenerator, at: Vector3, dir: Vector3, length: float, r0: float, depth: int,
		P: Dictionary, tips: Array, col: Color, sides: int) -> void:
	var segs: int = P.get("segs", 3)
	var pts := PackedVector3Array([at])
	var rs := PackedFloat32Array([r0])
	var d := dir
	var cur := at
	var taper: float = P.get("taper", 0.55)
	for s in segs:
		d = (d + _rdir(rng) * float(P.get("wiggle", 0.3)) + Vector3.UP * float(P.get("rise", 0.2))).normalized()
		cur += d * length / segs
		pts.append(cur)
		rs.append(lerpf(r0, r0 * taper, float(s + 1) / segs))
	var seed := rng.randi()
	if not (m.lod >= 1 and depth == 0):   # (the twigs: only up close - inside the clumps further off)
		_tube(m, seed, pts, rs, sides, col, float(P.get("lobe", 0.0)) * (1.0 if depth >= int(P.get("depth", 2)) else 0.4),
			float(P.get("twist", 0.0)), float(P.get("mottle", 0.0)), P.get("patch", col))
	if depth <= 0:
		tips.append([cur, d, length])
		return
	var kids := rng.randi_range(int(P.get("kids", Vector2i(2, 3)).x), int(P.get("kids", Vector2i(2, 3)).y))
	var from: float = P.get("from", 0.45)
	var turn0 := rng.randf() * TAU
	for k in kids:
		var t := rng.randf_range(from, 1.0) if k < kids - 1 else 1.0
		var fi := t * segs
		var i0 := mini(int(fi), segs - 1)
		var f := fi - i0
		var pt := pts[i0].lerp(pts[i0 + 1], f)
		var tan := (pts[i0 + 1] - pts[i0]).normalized()
		var rr := lerpf(rs[i0], rs[i0 + 1], f)
		var side := _perp(tan).rotated(tan, turn0 + k * 2.4 + rng.randf_range(-0.4, 0.4))
		var sa: float = float(P.get("spread", 0.7)) * rng.randf_range(0.75, 1.2)
		var kd := (tan * cos(sa) + side * sin(sa)).normalized()
		_limb(m, rng, pt, kd, length * float(P.get("shrink", 0.7)) * rng.randf_range(0.8, 1.15), rr * float(P.get("kid_r", 0.75)),
			depth - 1, P, tips, col, maxi(sides - 1, 3))


## An icosphere (unit): subdivisions 0 or 1 - [verts, tris].
static func _ico(sub: int) -> Array:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var vs: Array = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0), Vector3(0, -1, t), Vector3(0, 1, t),
		Vector3(0, -1, -t), Vector3(0, 1, -t), Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	for i in vs.size():
		vs[i] = (vs[i] as Vector3).normalized()
	var fs: Array = [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
	for s in sub:
		var mid := {}
		var nf: Array = []
		for f in fs:
			var ms: Array = []
			for e in 3:
				var a: int = f[e]
				var b: int = f[(e + 1) % 3]
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not mid.has(key):
					mid[key] = vs.size()
					vs.append(((vs[a] as Vector3) + (vs[b] as Vector3)).normalized())
				ms.append(mid[key])
			nf.append_array([[f[0], ms[0], ms[2]], [f[1], ms[1], ms[0]], [f[2], ms[2], ms[1]], [ms[0], ms[1], ms[2]]])
		fs = nf
	return [vs, fs]


static var _ico0: Array = _ico(0)   # (made once, when the script loads: only read on the workers)
static var _ico1: Array = _ico(1)


static func _ico_cached(sub: int) -> Array:
	return _ico0 if sub == 0 else _ico1


## A foliage clump: a lumpy ellipsoid at `c` (radii `r`), its normals bent
## toward the crown's (centre `cc`, radii `cr`) - the crown shaded as one -
## darker inside and below; leaf sprays (small triangles) breaking its outline.
static func _clump(m: M, seed: int, c: Vector3, r: Vector3, col: Color, cc: Vector3, cr: Vector3, sprays := 16, fleck := 0.0, fleck_col := Color()) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed
	if m.lod == 0 and m.leaf_shape != "":
		_leaf_cloud(m, rr, c, r, col, cc, cr, fleck, fleck_col)
		return
	var ico := _ico_cached(0 if m.far or (m.leaf_shape != "" and sprays > 0) else 1)   # (a tree's crown: coarse lumps, its leaf cards make the shape)
	var vs: Array = ico[0]
	var fs: Array = ico[1]
	var base := m.v.size()
	var ph := Vector3(rr.randf() * TAU, rr.randf() * TAU, rr.randf() * TAU)
	var lumpy := rr.randf_range(0.14, 0.26)
	m.leaf = 1.0
	for u: Vector3 in vs:
		var k := 1.0 + lumpy * (sin(u.x * 3.1 + ph.x) * sin(u.y * 2.7 + ph.y) + 0.6 * sin(u.z * 4.3 + ph.z + u.x * 2.0))
		var p := c + u * r * k
		var own := (u / r).normalized()
		var cn := ((p - cc) / cr)
		var depth := clampf(cn.length(), 0.0, 1.2)
		var n := own.lerp(cn.normalized(), 0.55).normalized()
		var hy := clampf((p.y - (cc.y - cr.y)) / (2.0 * cr.y), 0.0, 1.0)
		var shade := (0.45 + 0.45 * pow(hy, 0.8)) * (0.7 + 0.32 * minf(depth, 1.0)) * (0.92 + 0.16 * clampf(u.y, -1.0, 1.0))
		var cl := col * shade
		if fleck > 0.0 and rr.randf() < fleck:
			cl = fleck_col * (0.85 + 0.2 * hy)
		cl.a = 1.0
		m.add(p, n, cl)
	for f in fs:
		m.tri(base + f[0], base + f[1], base + f[2])
	if not m.far and m.leaf_shape == "":   # (a bush's: leaf sprays on its skin, tilted out - a ragged outline)
		for i in sprays:
			var u: Vector3 = vs[rr.randi() % vs.size()]
			var p := c + u * r * rr.randf_range(0.9, 1.05)
			var t1 := _perp(u).rotated(u, rr.randf() * TAU)
			var t2 := u.cross(t1)
			var tilt := rr.randf_range(0.5, 0.9)
			var a1 := (t1 * cos(tilt) + u * sin(tilt)).normalized()
			var len := minf(r.x, r.z) * rr.randf_range(0.22, 0.36)
			var n := ((p - cc) / cr).normalized().lerp(u, 0.4).normalized()
			var hy := clampf((p.y - (cc.y - cr.y)) / (2.0 * cr.y), 0.0, 1.0)
			var cl := col * ((0.55 + 0.55 * hy) * rr.randf_range(0.85, 1.15))
			if fleck > 0.0 and rr.randf() < fleck:
				cl = fleck_col * (0.85 + 0.2 * hy)
			cl.a = 1.0
			var a := m.add(p - a1 * len * 0.3, n, cl * 0.85)
			var b := m.add(p + t2 * len * 0.35, n, cl)
			var e := m.add(p + a1 * len, n, cl * 1.08)
			var f := m.add(p - t2 * len * 0.35, n, cl)
			m.quad(a, b, e, f)
	elif not m.far:   # (a tree's: leaf cards on its skin, tilted out - a leafy outline)
		var type: int = CARD_OF.get(m.leaf_shape, CARD_OVAL)
		for i in sprays:
			var u: Vector3 = vs[rr.randi() % vs.size()]
			var p := c + u * r * rr.randf_range(0.85, 1.0)
			var out := u
			var t1 := _perp(out).rotated(out, rr.randf() * TAU)
			var tilt := rr.randf_range(0.4, 0.9)
			var up := (t1 * cos(tilt) + out * sin(tilt)).normalized()
			var n := ((p - cc) / cr).normalized().lerp(out, 0.4).normalized()
			var side := n.cross(up).normalized()
			var len := minf(minf(r.x, r.z) * rr.randf_range(0.5, 0.75), 1.0)
			var hy := clampf((p.y - (cc.y - cr.y)) / (2.0 * cr.y), 0.0, 1.0)
			var cl := col * ((0.55 + 0.55 * hy) * rr.randf_range(0.85, 1.15))
			if fleck > 0.0 and rr.randf() < fleck:
				cl = cl.lerp(fleck_col, 0.5)
			cl.a = 1.0
			m.card(p - up * len * 0.3, side, up, len, len, n, cl, type)
	m.leaf = 0.0


## Clumps at the tips, shaded as one crown.
static func _crown(m: M, rng: RandomNumberGenerator, tips: Array, size: Vector2, flat: float, col: Color, extra: int,
		fleck := 0.0, fleck_col := Color(), sprays := 11) -> void:
	if tips.is_empty():
		return
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := -lo
	for t in tips:
		lo = lo.min(t[0])
		hi = hi.max(t[0])
	var rad := rng.randf_range(size.x, size.y)
	var cc := (lo + hi) * 0.5
	if m.far and tips.size() > MAX_CLUMPS:   # (far: a crown of so many clumps at most)
		tips = tips.duplicate()
		for i in tips.size():
			var j := rng.randi() % tips.size()
			var tmp = tips[i]
			tips[i] = tips[j]
			tips[j] = tmp
		tips.resize(MAX_CLUMPS)
	var cr := ((hi - lo) * 0.5 + Vector3.ONE * rad).max(Vector3.ONE * 0.5)
	for t in tips:
		var r := rad * rng.randf_range(0.75, 1.2) * (minf(pow(float(t[3]), 0.4), 1.7) if t.size() > 3 else 1.0)
		var seed := rng.randi()
		var tint := col.lightened(rng.randf_range(-0.07, 0.07))
		_clump(m, seed, t[0] + (t[1] as Vector3) * r * 0.3, Vector3(r, r * flat, r), tint, cc, cr, sprays, fleck, fleck_col)
	# (fill: clumps inside the crown - no see-through holes)
	for i in extra:
		var p := cc + Vector3(rng.randf_range(-0.6, 0.6) * (cr.x - rad), rng.randf_range(-0.2, 0.5) * (cr.y - rad * flat), rng.randf_range(-0.6, 0.6) * (cr.z - rad))
		var r := rad * rng.randf_range(0.9, 1.3)
		var seed := rng.randi()
		_clump(m, seed, p, Vector3(r, r * flat, r), col.darkened(0.08), cc, cr, sprays / 2, fleck, fleck_col)


# --- Leaves (the near meshes) -------------------------------------------------------

const CARD_LANCE := 0     # (the leaf cards' shapes - flora.gdshader cuts them)
const CARD_OVAL := 1
const CARD_BROAD := 2
const CARD_NEEDLES := 3
const CARD_FAN := 4
const CARD_OF := {"lance": CARD_LANCE, "oval": CARD_OVAL, "broad": CARD_BROAD, "needles": CARD_NEEDLES}

## Each tree's leaves: lance (olive: narrow, silver beneath), oval (oak, carob),
## broad (plane, fig: lobed, palm-veined), needles (pines: tufts).
const LEAVES := {"olive": "lance", "oak": "oval", "carob": "oval", "plane": "broad", "fig": "broad",
	"aleppo_pine": "needles", "stone_pine": "needles"}


## A clump up close: twigs out through it, and along them cards of leaves -
## sprays of single leaves the shader cuts out (each leaf its own shade), pine
## needles in crossed tufts; turned every way, facing out of the crown.
static func _leaf_cloud(m: M, rr: RandomNumberGenerator, c: Vector3, r: Vector3, col: Color, cc: Vector3, cr: Vector3, fleck: float, fleck_col: Color) -> void:
	var type: int = CARD_OF.get(m.leaf_shape, CARD_OVAL)
	var twigs := 5
	var starts: Array = []
	var ends: Array = []
	var out0 := ((c - cc) / cr)
	for k in twigs:
		var d := (_rdir(rr) + Vector3.UP * 0.3 + out0 * 0.8).normalized()
		var a := c - d * minf(r.x, r.y) * 0.4
		var e := c + d * r * 0.7
		starts.append(a)
		ends.append(e)
		_tube(m, rr.randi(), PackedVector3Array([a, e]), PackedFloat32Array([0.035 * minf(r.x, 2.0), 0.012]), 3, m.bark)
	var size: float = {CARD_LANCE: 0.6, CARD_OVAL: 0.62, CARD_BROAD: 0.4, CARD_NEEDLES: 0.62}[type]
	var cards := int(clampf(r.x * r.z * 26.0, 20.0, 64.0 if type != CARD_NEEDLES else 40.0))
	m.leaf = 1.0
	for s in cards:
		var k := s % twigs
		var t := rr.randf_range(0.25, 1.0)
		var at: Vector3 = (starts[k] as Vector3).lerp(ends[k], t)
		# (out to the clump's skin, mostly: a full crown, not a ball of twigs)
		var off := _rdir(rr)
		at = at.lerp(c + off * r * rr.randf_range(0.55, 1.0), 0.65)
		var cn := ((at - cc) / cr)
		var hy := clampf((at.y - (cc.y - cr.y)) / (2.0 * cr.y), 0.0, 1.0)
		var shade := (0.55 + 0.55 * pow(hy, 0.8)) * (0.72 + 0.32 * minf(cn.length(), 1.0))
		var lc := col * shade * rr.randf_range(0.88, 1.12)
		if fleck > 0.0 and rr.randf() < fleck * 0.5:
			lc = lc.lerp(fleck_col, 0.4)
		lc.a = 1.0
		var nrm := cn.normalized().lerp(off, 0.3).lerp(Vector3.UP, 0.25).normalized()
		var up := ((ends[k] - starts[k]) as Vector3).normalized().lerp(off, 0.6).normalized()
		up = (up - nrm * up.dot(nrm) * 0.7).normalized()
		var side := nrm.cross(up).normalized()
		var l := size * rr.randf_range(0.8, 1.2)
		var p0 := at - up * l * 0.35
		m.card(p0, side, up, l, l, nrm, lc, type)
		if type == CARD_NEEDLES and s % 2 == 0:   # (a tuft: two cards crossed)
			m.card(p0, (up.cross(side) - nrm * 0.0).normalized(), up, l, l, nrm, lc * 0.92, type)
	m.leaf = 0.0


# --- Trees -----------------------------------------------------------------------

const MAX_CLUMPS := 15
const TIP_BUDGET := 16    # (a crown's clumps at most: the nearest tips' clumps merged into bigger ones)


## Tips merged, nearest first, down to `budget` - each [point, direction, length, weight].
static func _merge_tips(tips: Array, budget: int) -> Array:
	var out: Array = []
	for t in tips:
		out.append([t[0], t[1], t[2], 1.0])
	while out.size() > budget:
		var best := INF
		var bi := 0
		var bj := 1
		for i in out.size():
			for j in range(i + 1, out.size()):
				var d: float = (out[i][0] as Vector3).distance_squared_to(out[j][0])
				if d < best:
					best = d
					bi = i
					bj = j
		var a: Array = out[bi]
		var b: Array = out[bj]
		var w: float = a[3] + b[3]
		out[bi] = [(a[0] * a[3] + b[0] * b[3]) / w, ((a[1] as Vector3) + (b[1] as Vector3)).normalized(), maxf(a[2], b[2]), w]
		out.remove_at(bj)
	return out

const TREE := {
	# trunk: height, radius, lean, stems; limbs (P); crown: clump radius, flatness, fill, sprays
	"olive": {"h": Vector2(1.2, 2.2), "r": Vector2(0.26, 0.4), "lean": 0.35, "stems": Vector2i(1, 3), "crown": Vector2(0.85, 1.15), "flat": 0.72, "fill": 3,
		"P": {"depth": 2, "kids": Vector2i(2, 3), "spread": 0.75, "rise": 0.12, "wiggle": 0.5, "shrink": 0.72, "len": 2.2, "from": 0.4,
			"lobe": 0.22, "twist": 5.0, "taper": 0.6, "segs": 3}, "fleck": 0.22, "fleck_col": Color(0.58, 0.63, 0.55)},
	"plane": {"h": Vector2(2.4, 3.4), "r": Vector2(0.42, 0.58), "lean": 0.08, "stems": Vector2i(1, 1), "crown": Vector2(1.8, 2.4), "flat": 0.8, "fill": 4,
		"P": {"depth": 2, "kids": Vector2i(3, 4), "spread": 0.8, "rise": 0.2, "wiggle": 0.25, "shrink": 0.7, "len": 5.5, "from": 0.35,
			"mottle": 0.35, "patch": Color(0.62, 0.6, 0.5), "taper": 0.55, "segs": 3}},
	"oak": {"h": Vector2(1.8, 2.8), "r": Vector2(0.34, 0.48), "lean": 0.1, "stems": Vector2i(1, 1), "crown": Vector2(1.5, 2.0), "flat": 0.78, "fill": 4,
		"P": {"depth": 2, "kids": Vector2i(3, 4), "spread": 0.85, "rise": 0.25, "wiggle": 0.4, "shrink": 0.68, "len": 3.4, "from": 0.35,
			"lobe": 0.08, "twist": 2.0, "taper": 0.55, "segs": 3}},
	"carob": {"h": Vector2(0.9, 1.4), "r": Vector2(0.28, 0.38), "lean": 0.15, "stems": Vector2i(1, 2), "crown": Vector2(1.5, 1.9), "flat": 0.75, "fill": 4,
		"P": {"depth": 2, "kids": Vector2i(3, 4), "spread": 1.0, "rise": 0.1, "wiggle": 0.35, "shrink": 0.66, "len": 2.6, "from": 0.3,
			"lobe": 0.1, "twist": 2.0, "taper": 0.55, "segs": 3}},
	"fig": {"h": Vector2(0.5, 0.9), "r": Vector2(0.16, 0.24), "lean": 0.5, "stems": Vector2i(3, 4), "crown": Vector2(1.1, 1.4), "flat": 0.8, "fill": 2,
		"P": {"depth": 2, "kids": Vector2i(2, 3), "spread": 0.8, "rise": 0.18, "wiggle": 0.35, "shrink": 0.7, "len": 2.0, "from": 0.4,
			"taper": 0.6, "segs": 3}},
	"aleppo_pine": {"h": Vector2(4.5, 7.0), "r": Vector2(0.24, 0.34), "lean": 0.22, "stems": Vector2i(1, 1), "crown": Vector2(1.1, 1.5), "flat": 0.55, "fill": 1,
		"P": {"depth": 2, "kids": Vector2i(3, 5), "spread": 1.05, "rise": 0.12, "wiggle": 0.35, "shrink": 0.62, "len": 3.2, "from": 0.55,
			"lobe": 0.05, "taper": 0.5, "segs": 3}, "sinuous": 0.35},
	"stone_pine": {"h": Vector2(6.5, 9.5), "r": Vector2(0.3, 0.42), "lean": 0.1, "stems": Vector2i(1, 1), "crown": Vector2(2.0, 2.6), "flat": 0.36, "fill": 4,
		"P": {"depth": 2, "kids": Vector2i(3, 4), "spread": 0.75, "rise": 0.05, "wiggle": 0.2, "shrink": 0.6, "len": 2.6, "from": 0.8,
			"taper": 0.55, "segs": 3}, "fork": Vector2i(3, 5), "fork_spread": 0.55},
	"snag": {"h": Vector2(2.5, 4.0), "r": Vector2(0.24, 0.34), "lean": 0.2, "stems": Vector2i(1, 1), "crown": Vector2.ZERO, "flat": 1.0, "fill": 0,
		"P": {"depth": 2, "kids": Vector2i(2, 3), "spread": 0.7, "rise": 0.25, "wiggle": 0.45, "shrink": 0.62, "len": 3.0, "from": 0.4,
			"lobe": 0.12, "twist": 4.0, "taper": 0.35, "segs": 3}},
	"glowtree": {"h": Vector2(2.5, 4.0), "r": Vector2(0.14, 0.22), "lean": 0.25, "stems": Vector2i(1, 2), "crown": Vector2(0.45, 0.7), "flat": 1.2, "fill": 0,
		"P": {"depth": 2, "kids": Vector2i(2, 3), "spread": 0.6, "rise": 0.35, "wiggle": 0.55, "shrink": 0.75, "len": 2.2, "from": 0.5,
			"lobe": 0.15, "twist": 8.0, "taper": 0.5, "segs": 4}},
}


static func _broadleaf(m: M, rng: RandomNumberGenerator, dname: String, sp: Dictionary) -> void:
	var D: Dictionary = TREE[dname]
	var P: Dictionary = (D["P"] as Dictionary).duplicate()
	var bark: Color = sp.get("bark", sp["color"])
	if dname == "snag":
		bark = sp["color"]
	var leaf: Color = sp["color"]
	m.sway = 0.3
	m.bark = bark
	m.leaf_shape = LEAVES.get(dname, "")
	m.silver = dname == "olive"
	var h := rng.randf_range(D["h"].x, D["h"].y)
	var r0 := rng.randf_range(D["r"].x, D["r"].y)
	var stems := rng.randi_range(D["stems"].x, D["stems"].y)
	var tips: Array = []
	var sides := 5 if m.far else 7
	var turn := rng.randf() * TAU
	for s in stems:
		var lean: float = float(D["lean"]) * (1.0 if stems > 1 else rng.randf_range(0.2, 1.0))
		var away := Vector3(cos(turn + s * TAU / stems), 0, sin(turn + s * TAU / stems))
		var dir := (Vector3.UP + away * lean).normalized()
		var rs := r0 / sqrt(float(stems))
		# The trunk: a bending tube, flared at its foot.
		var pts := PackedVector3Array([Vector3.ZERO + away * rs * 0.5 * float(stems > 1)])
		var rad := PackedFloat32Array([rs * 1.45])
		var cur: Vector3 = pts[0]
		var d := dir
		var n := 4
		for i in n:
			d = (d + _rdir(rng) * float(D.get("sinuous", 0.12)) + Vector3.UP * 0.05).normalized()
			cur += d * h / n
			pts.append(cur)
			rad.append(rs * lerpf(1.0, 0.72, float(i + 1) / n))
		rad[1] = rs * 1.08
		var seed := rng.randi()
		_tube(m, seed, pts, rad, sides, bark, float(P.get("lobe", 0.0)) * 1.4, float(P.get("twist", 0.0)),
			float(P.get("mottle", 0.0)), P.get("patch", bark))
		# The limbs: from the top (and up the trunk), spreading.
		var forks: int = rng.randi_range(D.get("fork", Vector2i(2, 3)).x, D.get("fork", Vector2i(2, 3)).y)
		if dname == "stone_pine":
			for k in forks:
				var side := _perp(d).rotated(d, k * TAU / forks + rng.randf_range(-0.3, 0.3))
				var a: float = float(D["fork_spread"]) * rng.randf_range(0.8, 1.2)
				_limb(m, rng, cur, (d * cos(a) + side * sin(a)).normalized(), float(P["len"]) * rng.randf_range(0.8, 1.2), rad[n] * 0.8,
					int(P["depth"]), P, tips, bark, sides - 2)
		else:
			for k in forks:
				var side := _perp(d).rotated(d, k * TAU / forks + rng.randf_range(-0.4, 0.4))
				var a: float = float(P["spread"]) * rng.randf_range(0.4, 0.9)
				_limb(m, rng, cur, (d * cos(a) + side * sin(a)).normalized(), float(P["len"]) * rng.randf_range(0.8, 1.15), rad[n] * 0.85,
					int(P["depth"]), P, tips, bark, sides - 2)
			if dname == "aleppo_pine":   # (its limbs up the trunk too)
				for k in rng.randi_range(2, 3):
					var t := rng.randf_range(0.55, 0.85)
					var at := pts[0].lerp(cur, t)
					var side := _perp(d).rotated(d, rng.randf() * TAU)
					_limb(m, rng, at, (side + Vector3.UP * 0.35).normalized(), float(P["len"]) * 0.7, rs * 0.4, 1, P, tips, bark, sides - 2)
	match dname:
		"snag":
			return
		"glowtree":
			m.glow = 0.85
			if tips.size() > MAX_CLUMPS:
				tips.resize(MAX_CLUMPS)
			for t in tips:
				var seed := rng.randi()
				var r := rng.randf_range(D["crown"].x, D["crown"].y)
				_clump(m, seed, t[0], Vector3(r, r * 1.3, r), leaf.lightened(rng.randf_range(-0.1, 0.15)), t[0], Vector3.ONE * r, 4)
			m.glow = 0.0
		_:
			_crown(m, rng, _merge_tips(tips, TIP_BUDGET), D["crown"], float(D["flat"]), leaf, int(D["fill"]), float(D.get("fleck", 0.0)), D.get("fleck_col", leaf))


## Mediterranean cypress: a tall dark flame of a column on a short trunk.
static func _cypress(m: M, rng: RandomNumberGenerator, col: Color, bark: Color) -> void:
	m.sway = 0.18
	var h := rng.randf_range(11.0, 16.0)
	var w := rng.randf_range(0.75, 1.15)
	var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * 0.03
	var seed := rng.randi()
	_tube(m, seed, PackedVector3Array([Vector3.ZERO, Vector3(0, 1.0, 0)]), PackedFloat32Array([0.3, 0.24]), 6, bark)
	var prof := func(t: float) -> float: return w * pow(sin(PI * clampf(pow(t, 0.75), 0.0, 1.0)), 0.55) * (1.0 - 0.15 * t)
	_lathe(m, rng, col, Vector3(0, 0.6, 0), h - 0.6, prof, lean, 0.18, 0.0, 9 if m.far else 18, 8 if m.far else 26, 1.6)


## A Greek fir: a dark cone of drooping tiers.
static func _fir(m: M, rng: RandomNumberGenerator, col: Color, bark: Color, frost: bool) -> void:
	m.sway = 0.3
	var h := rng.randf_range(10.0, 15.0)
	var w := h * rng.randf_range(0.2, 0.26)
	var seed := rng.randi()
	_tube(m, seed, PackedVector3Array([Vector3.ZERO, Vector3(0, h * 0.25, 0)]), PackedFloat32Array([0.32, 0.26]), 6, bark)
	var tiers := rng.randi_range(6, 9)
	var prof := func(t: float) -> float: return w * (1.0 - t) * (0.72 + 0.28 * fmod(t * tiers, 1.0)) + 0.05
	_lathe(m, rng, col, Vector3(0, h * 0.12, 0), h * 0.88, prof, Vector3.ZERO, 0.14, 0.4 if frost else 0.0, 8 if m.far else 14, tiers * (2 if m.far else 4), -0.25)


## A surface of revolution round a rising (leaning) axis, ruffled - with
## leaf sprays; `frost` whitens its tops.
static func _lathe(m: M, rng: RandomNumberGenerator, col: Color, at: Vector3, h: float, prof: Callable, lean: Vector3,
		ruffle: float, frost: float, sides: int, rings: int, upright := 0.0) -> void:
	m.leaf = 1.0
	var base := m.v.size()
	var ph := rng.randf() * TAU
	var ph2 := rng.randf() * TAU
	var bend := rng.randf_range(-0.4, 0.4)
	for j in rings + 1:
		var t := float(j) / rings
		var axis := at + Vector3(0, h * t, 0) + lean * h * t + Vector3(sin(t * 3.0 + ph) * 0.12, 0, cos(t * 2.0 + ph) * 0.12) * bend
		var r: float = prof.call(t)
		var r2: float = prof.call(minf(t + 0.02, 1.0))
		var slope := (r - r2) / (h * 0.02)
		for i in sides:
			var a := TAU * i / sides + t * 0.7
			var dv := Vector3(cos(a), 0, sin(a))
			var k := 1.0 + ruffle * (sin(a * 5.0 + t * 23.0 + ph) * 0.6 + sin(a * 9.0 - t * 41.0 + ph2) * 0.4) + rng.randf_range(-ruffle, ruffle) * 0.5
			var p := axis + dv * r * k
			var n := (dv + Vector3.UP * clampf(slope, -1.0, 2.0) * 0.6).normalized()
			var shade := (0.55 + 0.55 * pow(t, 0.6)) * (0.8 + 0.3 * clampf(k - 0.9, 0.0, 1.0)) * rng.randf_range(0.9, 1.1)
			var cl := col * shade
			if frost > 0.0 and rng.randf() < frost * (0.4 + 0.6 * clampf(slope, 0.0, 1.0)):
				cl = Color(0.86, 0.9, 0.95)
			cl.a = 1.0
			m.add(p, n, cl)
	for j in rings:
		for i in sides:
			var a := base + j * sides + i
			var b := base + j * sides + (i + 1) % sides
			m.quad(a, b, b + sides, a + sides)
	if not m.far:   # (sprays off its sides: a ragged outline - up close, many: its scale-leaf sprays)
		for i in rings * (14 if m.lod == 0 else 3):
			var t := rng.randf_range(0.05, 0.95)
			var r: float = prof.call(t)
			var a := rng.randf() * TAU
			var dv := Vector3(cos(a), 0, sin(a))
			var p := at + Vector3(0, h * t, 0) + lean * h * t + dv * r * 0.95
			var out := (dv + Vector3(0, rng.randf_range(-0.3, 0.6) + upright, 0)).normalized()
			var side := dv.cross(Vector3.UP).normalized().rotated(out, rng.randf_range(-0.6, 0.6))
			var len := maxf(r, 0.4) * rng.randf_range(0.5, 0.8) * (0.7 if m.lod == 0 else 1.0)
			var cl := col * ((0.6 + 0.5 * t) * rng.randf_range(0.9, 1.15))
			cl.a = 1.0
			var n := (dv + Vector3.UP * 0.4).normalized()
			m.card(p - out * len * 0.3, side, out, len * 0.8, len, n, cl, CARD_FAN)
	m.leaf = 0.0


## A palm: a curving ringed trunk, a crown of arching fronds.
static func _palm(m: M, rng: RandomNumberGenerator, col: Color, bark: Color) -> void:
	m.sway = 0.4
	var h := rng.randf_range(5.5, 8.0)
	var curve := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized() * rng.randf_range(0.6, 1.6)
	var pts := PackedVector3Array()
	var rs := PackedFloat32Array()
	var n := 6 if m.far else 14
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector3(0, h * t, 0) + curve * t * t)
		rs.append((0.24 - 0.06 * t) * (1.0 + (0.0 if m.far else 0.1 * float(i % 2))) + (0.12 if i == 0 else 0.0))
	var seed := rng.randi()
	_tube(m, seed, pts, rs, 5 if m.far else 7, bark)
	var top: Vector3 = pts[n]
	var fronds := rng.randi_range(11, 15)
	m.leaf = 1.0
	for f in fronds:
		var a := TAU * f / fronds + rng.randf_range(-0.2, 0.2)
		var out := Vector3(cos(a), 0, sin(a))
		var up := rng.randf_range(0.2, 0.9)
		var length := rng.randf_range(2.6, 3.6)
		var segs := 4 if m.far else 8
		var prev := top
		var dir := (out + Vector3.UP * up).normalized()
		var side := out.cross(Vector3.UP).normalized()
		var tint := col.lightened(rng.randf_range(-0.08, 0.08))
		for s in segs:
			var t := float(s + 1) / segs
			dir = (dir - Vector3.UP * 0.28).normalized()
			var nxt := prev + dir * length / segs
			var w := length * 0.28 * sin(PI * minf(t * 1.1, 1.0)) + 0.05
			var droop := Vector3.DOWN * w * 0.45
			var nn := side.cross(dir).normalized()
			if nn.y < 0.0:
				nn = -nn
			var cl := tint * (0.7 + 0.4 * t)
			cl.a = 1.0
			var i0 := m.add(prev, nn, cl)
			var i1 := m.add(nxt, nn, cl)
			var l := m.add(prev.lerp(nxt, 0.5) + side * w + droop, nn, cl * 0.9)
			var r := m.add(prev.lerp(nxt, 0.5) - side * w + droop, nn, cl * 0.9)
			m.tri(i0, i1, l)
			m.tri(i0, r, i1)
			prev = nxt
	m.leaf = 0.0


## A giant fungus: a pale stalk with stacked, spotted caps.
static func _fungus_tree(m: M, rng: RandomNumberGenerator, cap: Color, stem: Color, glow: float) -> void:
	m.sway = 0.2
	var h := rng.randf_range(5.0, 8.0)
	var pts := PackedVector3Array()
	var rs := PackedFloat32Array()
	var bend := _rdir(rng) * Vector3(1, 0, 1) * 0.8
	for i in 6:
		var t := i / 5.0
		pts.append(Vector3(0, h * t, 0) + bend * sin(t * 2.0))
		rs.append(lerpf(0.55, 0.28, t))
	var seed := rng.randi()
	_tube(m, seed, pts, rs, 6 if m.far else 10, stem, 0.08, 3.0)
	var caps := rng.randi_range(2, 4)
	for k in caps:
		var t := 1.0 - k * rng.randf_range(0.18, 0.26)
		var at := pts[0].lerp(pts[5], t)
		var r := rng.randf_range(1.6, 2.6) * (1.0 - 0.2 * k)
		var cs := rng.randi()
		m.glow = glow
		_clump(m, cs, at, Vector3(r, r * 0.28, r), cap.lightened(rng.randf_range(-0.1, 0.1)), at + Vector3(0, r * 0.2, 0), Vector3(r, r * 0.4, r), 0, 0.15, cap.lightened(0.5))
		m.glow = 0.0


## A tree of crystal: branching prisms, shards at the tips (glowing, rigid).
static func _crystal_tree(m: M, rng: RandomNumberGenerator, col: Color) -> void:
	m.sway = 0.0
	m.glow = 1.0
	var tips: Array = []
	var P := {"depth": 2, "kids": Vector2i(2, 3), "spread": 0.5, "rise": 0.25, "wiggle": 0.1, "shrink": 0.66, "from": 0.5, "taper": 0.7, "segs": 1}
	_limb(m, rng, Vector3.ZERO, Vector3.UP, rng.randf_range(2.5, 3.5), 0.3, 2, P, tips, col.darkened(0.2), 5)
	for t in tips:
		var at: Vector3 = t[0]
		var d: Vector3 = t[1]
		var len: float = t[2] * 0.7
		var seed := rng.randi()
		_tube(m, seed, PackedVector3Array([at, at + d * len]), PackedFloat32Array([0.12, 0.0]), 4, col.lightened(0.15))
	m.glow = 0.0


# --- Low plants --------------------------------------------------------------------

## A mound shrub (lentisk and kermes oak, thyme and sage cushions, rockrose):
## lumps of foliage on the ground, flecked with flowers.
static func _mound(m: M, rng: RandomNumberGenerator, col: Color, lo: int, hi: int, size: float, flat: float, fleck: float, fleck_col: Color) -> void:
	m.sway = 0.4
	var n := rng.randi_range(lo, hi)
	var lumps: Array = []
	for i in n:
		var r := rng.randf_range(0.55, 1.0) * size
		var at := Vector3(rng.randf_range(-0.7, 0.7) * size, r * flat * 0.6, rng.randf_range(-0.7, 0.7) * size)
		lumps.append([at, r])
	var cc := Vector3(0, size * flat * 0.6, 0)
	var cr := Vector3(size * 1.5, size * flat, size * 1.5)
	if size > 0.7 and not m.far:   # (a few stems under the bigger ones)
		for i in 3:
			var a := rng.randf() * TAU
			var seed := rng.randi()
			_tube(m, seed, PackedVector3Array([Vector3.ZERO, Vector3(cos(a) * 0.4, size * 0.8, sin(a) * 0.4)]), PackedFloat32Array([0.07, 0.04]), 4, Color(0.3, 0.25, 0.2))
	for l in lumps:
		var seed := rng.randi()
		var r: float = l[1]
		_clump(m, seed, l[0], Vector3(r, r * flat, r), col.lightened(rng.randf_range(-0.07, 0.07)), cc, cr, 8, fleck, fleck_col)


## Broom: a fan of green rods, yellow with flowers along their upper half.
static func _broom(m: M, rng: RandomNumberGenerator, col: Color, flower: Color) -> void:
	m.sway = 1.0
	var rods := rng.randi_range(11, 15)
	for i in rods:
		var a := rng.randf() * TAU
		var tilt := rng.randf_range(0.1, 0.5)
		var len := rng.randf_range(0.9, 1.6)
		var d := (Vector3.UP + Vector3(cos(a), 0, sin(a)) * tilt).normalized()
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.15)
		var tip := base + d * len
		var seed := rng.randi()
		_tube(m, seed, PackedVector3Array([base, base.lerp(tip, 0.5) + Vector3(0, 0, 0), tip]), PackedFloat32Array([0.025, 0.018, 0.008]), 3, col)
		m.leaf = 1.0
		for k in 4:
			var t := rng.randf_range(0.45, 1.0)
			var p := base.lerp(tip, t)
			var s := rng.randi()
			_blossom(m, s, p, 0.09, flower, d)
		m.leaf = 0.0


## Oleander: stems with clumps of lance leaves and pink (or white) flowers.
static func _oleander(m: M, rng: RandomNumberGenerator, col: Color, flower: Color) -> void:
	m.sway = 0.6
	var tips: Array = []
	for i in rng.randi_range(5, 7):
		var a := rng.randf() * TAU
		var d := (Vector3.UP + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.2, 0.6)).normalized()
		var len := rng.randf_range(1.4, 2.2)
		var seed := rng.randi()
		_tube(m, seed, PackedVector3Array([Vector3.ZERO, d * len * 0.5, d * len]), PackedFloat32Array([0.04, 0.03, 0.02]), 4, Color(0.36, 0.32, 0.24))
		tips.append([d * len, d, len])
	_crown(m, rng, tips, Vector2(0.45, 0.6), 0.85, col, 2, 0.35, flower, 8)


## A tiny blossom: a little five-pointed star.
static func _blossom(m: M, seed: int, at: Vector3, r: float, col: Color, up: Vector3) -> void:
	var rr := RandomNumberGenerator.new()
	rr.seed = seed
	var n := (up + _rdir(rr) * 0.6).normalized()
	var p := _perp(n)
	var q := n.cross(p)
	var cl := col * rr.randf_range(0.9, 1.08)
	cl.a = 1.0
	var c0 := m.add(at, n, cl)
	var first := -1
	var last := -1
	for i in 5:
		var a := TAU * i / 5.0
		var e := m.add(at + (p * cos(a) + q * sin(a)) * r, n, cl * 0.95)
		if last >= 0:
			m.tri(c0, last, e)
		else:
			first = e
		last = e
	m.tri(c0, last, first)


## A clump of grass blades (a carpet when many): each blade bent in two,
## darker at its foot; golden grass with seed heads; normals turned up -
## lit like the ground under it.
static func _grass_clump(m: M, rng: RandomNumberGenerator, col: Color, blades: int, spread: float, hh: Vector2, lean: float, heads: bool) -> void:
	m.sway = 3.5
	m.fade = GRASS_FADE
	m.leaf = 1.0
	if m.far:
		blades /= 2
	for i in blades:
		var a := rng.randf() * TAU
		var rad := spread * sqrt(rng.randf())
		var base := Vector3(cos(a), 0, sin(a)) * rad + Vector3(0, -0.03, 0)
		var out := Vector3(cos(a + rng.randf_range(-0.6, 0.6)), 0, sin(a + rng.randf_range(-0.6, 0.6)))
		var h := rng.randf_range(hh.x, hh.y)
		var l := lean * rng.randf_range(0.4, 1.2) * (0.5 + rad / maxf(spread, 0.01))
		var side := Vector3(-out.z, 0, out.x) * rng.randf_range(0.012, 0.022) * (1.0 + h)
		var mid := base + out * l * h * 0.3 + Vector3(0, h * 0.55, 0)
		var tip := base + out * l * h + Vector3(0, h, 0) - out * 0.0
		var cl := col.lightened(rng.randf_range(-0.1, 0.12))
		if rng.randf() < 0.12:
			cl = cl.lerp(Color(0.72, 0.64, 0.36), 0.5)   # (a dry blade here and there)
		var nb := side.cross(tip - base).normalized()
		var n := Vector3.UP.lerp(nb if nb.y >= 0.0 else -nb, 0.3).normalized()
		var dark := cl * 0.55
		dark.a = 1.0
		cl.a = 1.0
		var b0 := m.add(base - side, n, dark)
		var b1 := m.add(base + side, n, dark)
		var m0 := m.add(mid - side * 0.7, n, cl * 0.85)
		var m1 := m.add(mid + side * 0.7, n, cl * 0.85)
		var t := m.add(tip, n, cl * 1.1)
		m.quad(b0, b1, m1, m0)
		m.tri(m0, m1, t)
		if heads and rng.randf() < 0.45:
			var hc := cl.lightened(0.18)
			var hd := (tip - mid).normalized()
			var hs := Vector3(-hd.z, 0, hd.x).normalized() * 0.025
			var h0 := m.add(tip - hs, n, hc)
			var h1 := m.add(tip + hs, n, hc)
			var h2 := m.add(tip + hd * 0.12, n, hc)
			m.tri(h0, h1, h2)
	m.leaf = 0.0
	m.fade = 0.0


## Reeds by the shore: tall stems with long leaves, a plume on top.
static func _reeds(m: M, rng: RandomNumberGenerator, col: Color) -> void:
	m.sway = 1.6
	for i in rng.randi_range(7, 11):
		var a := rng.randf() * TAU
		var base := Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.6)
		var h := rng.randf_range(1.6, 2.8)
		var d := (Vector3.UP + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.0, 0.15)).normalized()
		var seed := rng.randi()
		_tube(m, seed, PackedVector3Array([base, base + d * h * 0.5, base + d * h]), PackedFloat32Array([0.03, 0.025, 0.012]), 3, col.darkened(0.1))
		m.leaf = 1.0
		for k in (1 if m.far else 4):
			var t := rng.randf_range(0.15, 0.8)
			var at := base + d * h * t
			var b := rng.randf() * TAU
			var out := Vector3(cos(b), 0, sin(b))
			var len := rng.randf_range(0.5, 0.9)
			var tip := at + out * len * 0.7 + Vector3(0, len * 0.25, 0)
			var side := Vector3(-out.z, 0, out.x) * 0.035
			var n := Vector3.UP
			var cl := col.lightened(rng.randf_range(-0.05, 0.1))
			cl.a = 1.0
			var i0 := m.add(at - side, n, cl * 0.8)
			var i1 := m.add(at + side, n, cl * 0.8)
			var i2 := m.add(tip, n, cl)
			m.tri(i0, i1, i2)
		var s := rng.randi()
		_tube(m, s, PackedVector3Array([base + d * h, base + d * (h + 0.2) + Vector3(0.05, 0, 0), base + d * (h + 0.45) + Vector3(0.12, -0.05, 0)]),
			PackedFloat32Array([0.04, 0.06, 0.0]), 3, Color(0.7, 0.6, 0.48))
		m.leaf = 0.0


## Poppies and anemones: thin stems, a cup of petals each, leaves at their feet.
static func _cup_flowers(m: M, rng: RandomNumberGenerator, col: Color, stem: Color, petals: int, dark_eye: bool) -> void:
	m.sway = 2.5
	m.fade = FLOWER_FADE
	for i in rng.randi_range(8, 13):
		var at := Vector3(rng.randf_range(-0.45, 0.45), 0, rng.randf_range(-0.45, 0.45))
		var h := rng.randf_range(0.22, 0.5)
		var top := at + Vector3(rng.randf_range(-0.06, 0.06), h, rng.randf_range(-0.06, 0.06))
		var seed := rng.randi()
		_tube(m, seed, PackedVector3Array([at, top]), PackedFloat32Array([0.008, 0.006]), 3, stem)
		m.leaf = 1.0
		var r := rng.randf_range(0.06, 0.09)
		var cl := col.lightened(rng.randf_range(-0.08, 0.08))
		cl.a = 1.0
		var eye := m.add(top, Vector3.UP, Color(0.08, 0.06, 0.06) if dark_eye or col.r > 0.7 else Color(0.9, 0.8, 0.2))
		var ring: Array = []
		for k in petals * 2:
			var a := TAU * k / (petals * 2)
			var rr := r * (1.0 if k % 2 == 0 else 0.7)
			ring.append(m.add(top + Vector3(cos(a) * rr, r * 0.55, sin(a) * rr), Vector3(cos(a), 1.5, sin(a)).normalized(), cl))
		for k in ring.size():
			m.tri(eye, ring[k], ring[(k + 1) % ring.size()])
		m.leaf = 0.0
	_leaves_low(m, rng, stem, 5, 0.15)
	m.fade = 0.0


## Daisies (chamomile): white rays round a yellow eye, many to a clump.
static func _daisies(m: M, rng: RandomNumberGenerator, col: Color, stem: Color) -> void:
	m.sway = 2.5
	m.fade = FLOWER_FADE
	for i in rng.randi_range(10, 16):
		var at := Vector3(rng.randf_range(-0.4, 0.4), 0, rng.randf_range(-0.4, 0.4))
		var top := at + Vector3(0, rng.randf_range(0.1, 0.3), 0)
		var seed := rng.randi()
		_tube(m, seed, PackedVector3Array([at, top]), PackedFloat32Array([0.006, 0.005]), 3, stem)
		m.leaf = 1.0
		_blossom(m, rng.randi(), top, rng.randf_range(0.04, 0.06), col, Vector3.UP * 3.0)
		var e := m.add(top + Vector3(0, 0.006, 0), Vector3.UP, Color(0.95, 0.78, 0.15))
		var e1 := m.add(top + Vector3(0.012, 0.004, 0), Vector3.UP, Color(0.95, 0.78, 0.15))
		var e2 := m.add(top + Vector3(-0.006, 0.004, 0.011), Vector3.UP, Color(0.95, 0.78, 0.15))
		m.tri(e, e1, e2)
		m.leaf = 0.0
	_leaves_low(m, rng, stem, 6, 0.12)
	m.fade = 0.0


## Asphodels: tall stalks of white-pink starry flowers over grassy leaves.
static func _asphodel(m: M, rng: RandomNumberGenerator, col: Color, stem: Color) -> void:
	m.sway = 1.6
	m.fade = FLOWER_FADE
	for i in rng.randi_range(1, 3):
		var at := Vector3(rng.randf_range(-0.15, 0.15), 0, rng.randf_range(-0.15, 0.15))
		var h := rng.randf_range(0.7, 1.2)
		var top := at + Vector3(rng.randf_range(-0.1, 0.1), h, rng.randf_range(-0.1, 0.1))
		var seed := rng.randi()
		_tube(m, seed, PackedVector3Array([at, top]), PackedFloat32Array([0.014, 0.008]), 3, stem)
		m.leaf = 1.0
		for k in (3 if m.far else 9):
			var t := rng.randf_range(0.55, 1.0)
			_blossom(m, rng.randi(), at.lerp(top, t) + _rdir(rng) * 0.03, 0.03, col, Vector3.UP)
		m.leaf = 0.0
	_leaves_low(m, rng, stem, 9, 0.4)
	m.fade = 0.0


## Thistles: spiky grey-green leaves, purple globe heads.
static func _thistle(m: M, rng: RandomNumberGenerator, col: Color, stem: Color) -> void:
	m.sway = 1.2
	m.fade = FLOWER_FADE
	_leaves_low(m, rng, stem, 8, 0.3)
	for i in rng.randi_range(1, 3):
		var at := Vector3(rng.randf_range(-0.1, 0.1), 0, rng.randf_range(-0.1, 0.1))
		var top := at + Vector3(rng.randf_range(-0.1, 0.1), rng.randf_range(0.45, 0.8), rng.randf_range(-0.1, 0.1))
		var seed := rng.randi()
		_tube(m, seed, PackedVector3Array([at, top]), PackedFloat32Array([0.015, 0.01]), 3, stem)
		m.leaf = 1.0
		_clump(m, rng.randi(), top, Vector3(0.05, 0.05, 0.05), stem, top, Vector3.ONE * 0.05, 0)
		_clump(m, rng.randi(), top + Vector3(0, 0.05, 0), Vector3(0.045, 0.035, 0.045), col, top, Vector3.ONE * 0.05, 0)
		m.leaf = 0.0
	m.fade = 0.0


## Leaves at a plant's foot: blades splayed low.
static func _leaves_low(m: M, rng: RandomNumberGenerator, col: Color, n: int, len: float) -> void:
	m.leaf = 1.0
	for i in n:
		var a := rng.randf() * TAU
		var out := Vector3(cos(a), 0, sin(a))
		var l := len * rng.randf_range(0.6, 1.1)
		var tip := out * l + Vector3(0, l * 0.35, 0)
		var side := Vector3(-out.z, 0, out.x) * l * 0.15
		var cl := col * rng.randf_range(0.75, 1.0)
		cl.a = 1.0
		var i0 := m.add(-side * 0.3, Vector3.UP, cl * 0.7)
		var i1 := m.add(out * l * 0.4 + side + Vector3(0, l * 0.2, 0), Vector3.UP, cl)
		var i2 := m.add(tip, Vector3.UP, cl)
		var i3 := m.add(out * l * 0.4 - side + Vector3(0, l * 0.2, 0), Vector3.UP, cl)
		m.quad(i0, i1, i2, i3)
	m.leaf = 0.0


## (CosmosWarm) A small mesh of every vertex layout and leaf card the trees use:
## a twig and a card of each shape - drawn once at the title with leaf_flora.gdshader.
static func warm_arrays() -> Array:
	var m := M.new()
	_tube(m, 1, PackedVector3Array([Vector3.ZERO, Vector3(0, 1, 0)]), PackedFloat32Array([0.1, 0.05]), 4, Color(0.4, 0.3, 0.2))
	m.leaf = 1.0
	for t in 5:
		m.silver = t == 0
		m.card(Vector3(t * 0.3 - 0.6, 0.5, 0), Vector3.RIGHT, Vector3.UP, 0.3, 0.3, Vector3.BACK, Color(0.3, 0.45, 0.2), t)
	return m.arrays()


# --- The alien worlds' (older) plants: crystals, fungi, cacti -------------------------

static func _crystal(rng: RandomNumberGenerator, col: Color) -> Array:
	var m := M.new()
	m.glow = 1.0
	m.sway = 0.0
	for i in rng.randi_range(3, 7):
		var dir := Vector3(rng.randf_range(-0.5, 0.5), 1.0, rng.randf_range(-0.5, 0.5)).normalized()
		var h := rng.randf_range(0.5, 1.6)
		var r := rng.randf_range(0.08, 0.22)
		var base := Vector3(rng.randf_range(-0.25, 0.25), -0.1, rng.randf_range(-0.25, 0.25))
		var c := col.lightened(rng.randf_range(-0.15, 0.2))
		_tube(m, rng.randi(), PackedVector3Array([base, base + dir * h]), PackedFloat32Array([r, r]), 6, c)
		_tube(m, rng.randi(), PackedVector3Array([base + dir * h, base + dir * (h + r * 2.2)]), PackedFloat32Array([r, 0.0]), 6, c.lightened(0.2))
	return m.arrays()


static func _fungus(rng: RandomNumberGenerator, cap: Color, stem: Color, glow := 0.5) -> Array:
	var m := M.new()
	m.sway = 0.3
	for i in rng.randi_range(1, 4):
		var at := Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		var h := rng.randf_range(0.4, 1.6)
		var r := rng.randf_range(0.3, 0.8) * h
		_tube(m, rng.randi(), PackedVector3Array([at, at + Vector3(0, h, 0)]), PackedFloat32Array([r * 0.2, r * 0.15]), 6, stem)
		m.glow = glow
		var top := at + Vector3(0, h, 0)
		_clump(m, rng.randi(), top, Vector3(r, r * 0.45, r), cap.lightened(rng.randf_range(-0.1, 0.1)), top, Vector3(r, r * 0.45, r), 0)
		m.glow = 0.0
	return m.arrays()


static func _cactus(rng: RandomNumberGenerator, col: Color) -> Array:
	var m := M.new()
	m.sway = 0.0
	var h := rng.randf_range(1.5, 3.5)
	_tube(m, rng.randi(), PackedVector3Array([Vector3.ZERO, Vector3(0, h * 0.5, 0), Vector3(0, h, 0), Vector3(0, h + 0.2, 0)]),
		PackedFloat32Array([0.3, 0.29, 0.26, 0.05]), 10, col, 0.06)
	for i in rng.randi_range(0, 3):
		var a := rng.randf() * TAU
		var d := Vector3(cos(a), 0, sin(a))
		var y := h * rng.randf_range(0.3, 0.6)
		var elbow := Vector3(0, y, 0) + d * 0.7
		var up := rng.randf_range(0.5, 1.0)
		_tube(m, rng.randi(), PackedVector3Array([Vector3(0, y, 0), elbow, elbow + Vector3(0, up, 0), elbow + Vector3(0, up + 0.12, 0)]),
			PackedFloat32Array([0.16, 0.16, 0.14, 0.03]), 6, col, 0.06)
	return m.arrays()


# --- Where they grow ---------------------------------------------------------------

## How likely a plant of `sp` is at direction `d` from the land around - before
## its height is known: woods or open land, its own territories (0..1).
static func cluster(sp: Dictionary, d: Vector3, radius: float) -> float:
	var nz: FastNoiseLite = sp["noise"]
	var p := d * radius
	var woods := smoothstep(-0.08, 0.28, nz.get_noise_3dv(p / 340.0))   # (forests and groves; the open land between)
	var wood: float = sp["wood"]
	var lone: float = sp["lone"]
	var here: float
	if wood >= 0.0:
		here = lerpf(1.0, lone + (1.0 - lone) * woods, wood)
	else:
		here = lerpf(1.0, lone + (1.0 - lone) * (1.0 - woods), -wood)
	if here <= 0.001:
		return 0.0
	var own := smoothstep(-0.2, 0.3, nz.get_noise_3dv(p / float(sp["group"]) + (sp["off"] as Vector3)))   # (its territories)
	var keep: float = 0.35 if sp["kind"] == "grass" else 0.08   # (grass: everywhere, thicker in its patches)
	return here * (keep + (1.0 - keep) * own)


## How well it grows `h` m up (slope 0 flat .. 1 sheer) - 0..1.
static func site(sp: Dictionary, shape: PlanetShape, h: float, slope: float) -> float:
	var amp := maxf(shape.amp, 1.0)
	var hn := h / amp
	var lo: float = sp["min_h"]
	var hi: float = sp["max_h"]
	var k := smoothstep(lo - 0.04, lo + 0.05, hn) * (1.0 - smoothstep(hi - 0.12, hi + 0.04, hn))
	var ms: float = sp["max_slope"]
	k *= 1.0 - smoothstep(ms * 0.55, ms, slope)
	if shape.sea > 0:
		if h < 0.6 and sp["kind"] != "crystal":
			return 0.0
		if bool(sp.get("shore", false)):
			k *= 1.0 - smoothstep(amp * 0.05, amp * 0.14, h)
		elif sp["kind"] != "crystal":
			k *= smoothstep(amp * 0.03, amp * 0.07, h)   # (not on the beach's sand)
		if bool(sp.get("lowland", false)):   # (plane trees: down in the valleys, by the shores)
			k *= 1.0 - smoothstep(amp * 0.15, amp * 0.3, h)
	var green: float = sp.get("green", 0.0)
	if green != 0.0:
		var lush := _lush(shape, h)
		k *= lerpf(1.0, lush, green) if green > 0.0 else lerpf(1.0, 1.0 - lush * 0.85, -green)
	return clampf(k, 0.0, 1.0)


## How green the ground is there (0..1): the terrain's mid colour, green, below the hills.
static func _lush(shape: PlanetShape, h: float) -> float:
	var c: Color = shape.look.get("land_mid", Color(0.4, 0.4, 0.3))
	var g := clampf((c.g - maxf(c.r, c.b)) * 5.0, 0.0, 1.0)
	var hl := h / (maxf(shape.amp, 1.0) * 1.8)
	return g * (1.0 - smoothstep(0.32, 0.5, hl))


## Old rule (kept for callers): does it grow there at all.
static func grows(sp: Dictionary, shape: PlanetShape, h: float, slope: float) -> bool:
	return site(sp, shape, h, slope) > 0.0


## A size: most middling, some saplings, now and then an old giant.
static func size_of(sp: Dictionary, rng: RandomNumberGenerator) -> float:
	var s: Vector2 = sp["size"]
	var u := (rng.randf() + rng.randf() + rng.randf()) / 3.0
	var r := rng.randf()
	if r < 0.1:
		return s.x * rng.randf_range(0.3, 0.6)   # (a sapling)
	if r > 0.95:
		return s.y * rng.randf_range(1.1, 1.45)   # (an old giant)
	return lerpf(s.x, s.y, u)


## (Worker) A finest cell's plants: every species' candidates, each kept by
## its cluster and site chances; transforms (relative to `centre`) into
## `out[k]`, the solid ones' trunks into `solids` ([point, radius, height]).
## Each species its own seed - a coarse cell (only the solid ones) puts them
## exactly where its finer cells will.
static func scatter(flora: Array, shape: PlanetShape, radius: float, cell_seed: int, n: Vector3, u: Vector3, v: Vector3,
		a0: float, b0: float, span: float, centre: Vector3, coarse: bool, digs: PackedFloat64Array, out: Dictionary, solids: Array, stands := true) -> void:
	var area := pow(span * radius * 0.9, 2.0) / 100.0   # (densities are a 100 m2)
	var step := 1.2 / radius
	var rng := RandomNumberGenerator.new()
	# (the cell sampled, 3 x 3: each species' best chance in it bounds its candidates -
	# few tried where it hardly grows; a function of the cell, so the same coarse or fine)
	var sd: Array = []
	var sh: Array = []
	for j in 3:
		for i in 3:
			var d := PlanetShape.face_dir(n, u, v, a0 + span * i * 0.5, b0 + span * j * 0.5)
			sd.append(d)
			sh.append(shape.height(d))
	for k in flora.size():
		var sp: Dictionary = flora[k]
		var solid: float = sp["solid"]
		if coarse and solid <= 0.0 or not stands and FloraLods.is_stand(sp):
			continue   # (the trees and shrubs: FloraLods carries them, on every patch)
		var bound := 0.0
		for q in 9:
			bound = maxf(bound, cluster(sp, sd[q], radius) * site(sp, shape, sh[q], 0.0))
		bound = minf(1.0, bound * 1.6 + 0.06)
		rng.seed = hash([cell_seed, k])
		var m := int(float(sp["density"]) * area * bound + rng.randf())
		var list: Array = out.get(k, [])
		var tilt: float = sp["tilt"]
		var tall: float = sp["tall"]
		for i in m:
			# (cheap first: where, and the woods' and its territories' chance - most go here)
			var d := PlanetShape.face_dir(n, u, v, a0 + rng.randf() * span, b0 + rng.randf() * span)
			var pick := rng.randf() * bound
			var ch := cluster(sp, d, radius)
			if pick > ch:
				continue
			if shape.cleared(d) or shape.dug_here(d, digs) or shape.bare(d):
				continue
			var h := shape.height(d)
			var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var slope := absf(shape.height((d + t * step).normalized()) - h) / 1.2
			var st := site(sp, shape, h, slope)
			if pick > ch * st:
				continue
			var sc := size_of(sp, rng)
			var turn := rng.randf() * TAU
			var lean := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)) * tilt
			var squash := Vector3(rng.randf_range(0.88, 1.12), rng.randf_range(0.88, 1.15), rng.randf_range(0.88, 1.12))
			if coarse and sc < float(sp["size"].x) * 0.65:
				continue   # (the saplings: only near)
			var x := t.rotated(d, turn)
			var b := Basis(x, d, x.cross(d))
			b = b * Basis.from_euler(lean) * Basis.from_scale(squash * sc)
			var at := d * (radius + h - 0.06 * sc - slope * 0.4 * sc)
			list.append(Transform3D(b, at - centre))
			if solid > 0.0:
				solids.append([at, solid * sc, tall * sc])
		if not list.is_empty():
			out[k] = list
