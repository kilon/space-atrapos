class_name CosmosFauna
extends RefCounted
## A planet's animals in the 3D game (stage 3): species designed from the
## planet's seed and type - a body plan (two, four or six legs, or none: a
## crawler), a neck and head, a tail, horns or crests, colours and a pattern
## (stripes, spots, plain) from the planet's palette, a temper (grazers that
## flee, skittish runners, predators that hunt you - the biggest of them the
## planet's monster) - and their names, made up from syllables. CosmosCreature
## builds and drives one.
##   var kinds := CosmosFauna.design(shape, seed, type)

const COUNT_BY_TYPE := {"ocean": 4, "ice": 3, "volcanic": 3, "moon": 1, "rocky": 2}
const SYL := ["ka", "ro", "the", "mi", "so", "ny", "xa", "dra", "phi", "lo", "ki", "ta", "ser", "on", "ix", "py", "gro", "la", "ze", "mo"]
const TAILS := ["don", "ros", "ax", "ops", "ion", "yx", "eus", "as"]


## The 2D game's animals (its SurfaceCreature.SPECIES) in 3D: each species a
## body plan (PLANS) with its own build - proportions, horns or antlers, a
## shell, wings, a mushroom cap, glow - its colours and pattern, and its 2D
## numbers (height px / 55 = metres, speeds px/s / 30 = m/s, health, bite).
## [plan, 2D name, height px, walk, run, temper, hp, bite, c1, c2, pattern, extras]
const PLANS := {
	"hoof": {"legs": 4, "body": Vector3(0.6, 0.7, 1.4), "leg_len": 0.9, "leg_w": 0.12, "neck": 0.6, "head": 0.34, "snout": 0.35, "tail": 0.3},
	"small": {"legs": 4, "body": Vector3(0.5, 0.5, 0.8), "leg_len": 0.35, "leg_w": 0.1, "neck": 0.1, "head": 0.34, "snout": 0.15, "tail": 0.2},
	"canine": {"legs": 4, "body": Vector3(0.5, 0.55, 1.3), "leg_len": 0.7, "leg_w": 0.11, "neck": 0.3, "head": 0.34, "snout": 0.45, "tail": 0.9},
	"heavy": {"legs": 4, "body": Vector3(1.0, 0.9, 1.6), "leg_len": 0.55, "leg_w": 0.22, "neck": 0.0, "head": 0.5, "snout": 0.3, "tail": 0.25},
	"serpent": {"legs": 0, "body": Vector3(0.35, 0.3, 3.0), "leg_len": 0.0, "leg_w": 0.1, "neck": 0.0, "head": 0.3, "snout": 0.2, "tail": 1.4},
	"shell": {"legs": 4, "body": Vector3(0.8, 0.45, 1.0), "leg_len": 0.2, "leg_w": 0.12, "neck": 0.2, "head": 0.25, "snout": 0.05, "tail": 0.1, "shell": 1.0},
	"insect": {"legs": 6, "body": Vector3(0.45, 0.35, 1.2), "leg_len": 0.55, "leg_w": 0.05, "neck": 0.1, "head": 0.25, "snout": 0.0, "tail": 0.5, "splay": true},
	"bird": {"legs": 2, "body": Vector3(0.45, 0.5, 0.7), "leg_len": 0.3, "leg_w": 0.05, "neck": 0.1, "head": 0.3, "snout": 0.1, "tail": 0.4, "wings": 1.6},
	"flyer": {"legs": 0, "body": Vector3(0.25, 0.25, 0.8), "leg_len": 0.0, "leg_w": 0.05, "neck": 0.0, "head": 0.2, "snout": 0.0, "tail": 0.6, "wings": 1.4, "alt": 2.5},
	"drift": {"legs": 0, "body": Vector3(0.9, 0.7, 0.9), "leg_len": 0.0, "leg_w": 0.05, "neck": 0.0, "head": 0.0, "snout": 0.0, "tail": 0.0, "tentacles": 6, "alt": 2.0},
	"grub": {"legs": 0, "body": Vector3(0.55, 0.5, 1.6), "leg_len": 0.0, "leg_w": 0.1, "neck": 0.0, "head": 0.35, "snout": 0.0, "tail": 0.2},
}
const SPECIES := {
	# Forest worlds (the 2D "fo" set: ocean worlds).
	"goat": ["hoof", "Cretan wild goat", 74, 40, 150, "grazer", 30, 6, Color(0.55, 0.42, 0.3), Color(0.85, 0.78, 0.65), 0, {"horns": 2, "herd": true}],
	"sheep": ["hoof", "sheep", 58, 28, 90, "grazer", 30, 0, Color(0.9, 0.88, 0.82), Color(0.25, 0.22, 0.2), 0, {"body": Vector3(0.8, 0.8, 1.3), "neck": 0.3, "herd": true}],
	"deer": ["hoof", "red deer", 118, 45, 170, "grazer", 40, 8, Color(0.55, 0.3, 0.16), Color(0.85, 0.7, 0.5), 0, {"antlers": 1.0, "leg_len": 1.1}],
	"donkey": ["hoof", "donkey", 96, 30, 80, "grazer", 50, 7, Color(0.48, 0.45, 0.42), Color(0.85, 0.82, 0.78), 0, {"ears": 0.4}],
	"hare": ["small", "brown hare", 34, 50, 210, "skittish", 10, 0, Color(0.55, 0.42, 0.28), Color(0.9, 0.85, 0.75), 0, {"ears": 0.5}],
	"fox": ["canine", "red fox", 46, 55, 180, "skittish", 20, 0, Color(0.85, 0.42, 0.15), Color(0.95, 0.92, 0.88), 0, {"ears": 0.25, "tail": 1.0}],
	"tortoise": ["shell", "Greek tortoise", 24, 9, 9, "slow", 40, 0, Color(0.42, 0.4, 0.22), Color(0.7, 0.6, 0.35), 2, {}],
	"owl": ["bird", "little owl", 30, 0, 170, "bird", 10, 0, Color(0.5, 0.4, 0.3), Color(0.9, 0.85, 0.7), 2, {"wings": 1.2}],
	"eagle": ["bird", "golden eagle", 56, 0, 120, "soar", 30, 0, Color(0.35, 0.24, 0.14), Color(0.85, 0.65, 0.3), 0, {"wings": 2.4, "alt": 9.0}],
	"wolf": ["canine", "grey wolf", 66, 45, 165, "predator", 45, 9, Color(0.45, 0.45, 0.45), Color(0.82, 0.8, 0.75), 0, {"ears": 0.2, "herd": true}],
	"boar": ["heavy", "wild boar", 62, 35, 205, "predator", 60, 11, Color(0.28, 0.2, 0.15), Color(0.5, 0.4, 0.32), 0, {"horns": 2, "snout": 0.4}],
	"snake": ["serpent", "Aesculapian snake", 26, 22, 30, "predator", 15, 7, Color(0.35, 0.32, 0.15), Color(0.85, 0.75, 0.3), 1, {}],
	"tigrokeros": ["hoof", "striped tigrokeros", 76, 42, 160, "grazer", 35, 7, Color(0.9, 0.55, 0.2), Color(0.12, 0.1, 0.08), 1, {"horns": 2, "herd": true}],
	"mykelephas": ["heavy", "mushroom mammoth", 130, 24, 60, "grazer", 120, 16, Color(0.45, 0.4, 0.38), Color(0.75, 0.2, 0.15), 2, {"cap": 1.0, "snout": 0.9, "horns": 2, "leg_len": 0.9}],
	"selas": ["hoof", "glowing selas stag", 116, 44, 175, "grazer", 40, 9, Color(0.88, 0.92, 0.95), Color(0.4, 0.9, 1.0), 2, {"antlers": 1.2, "glow": 1.5}],
	"capslug": ["grub", "capped slug", 66, 12, 12, "grazer", 50, 0, Color(0.5, 0.35, 0.55), Color(0.9, 0.6, 0.3), 2, {"cap": 1.0}],
	"toad": ["small", "bubble toad", 40, 40, 170, "skittish", 12, 0, Color(0.35, 0.55, 0.25), Color(0.9, 0.85, 0.4), 2, {"neck": 0.0, "leg_len": 0.25}],
	"pangolin": ["shell", "moss pangolin", 40, 20, 20, "slow", 50, 0, Color(0.3, 0.45, 0.22), Color(0.55, 0.7, 0.35), 2, {"tail": 0.8}],
	"aeromanta": ["flyer", "aeromanta", 50, 0, 140, "soar", 30, 0, Color(0.2, 0.35, 0.6), Color(0.85, 0.9, 1.0), 0, {"wings": 2.6, "alt": 6.0}],
	"jelly": ["drift", "sky jelly", 70, 14, 14, "drift", 20, 0, Color(0.9, 0.5, 0.75), Color(0.6, 0.85, 1.0), 2, {"glow": 1.2}],
	"harpyx": ["bird", "harpyx raptor", 82, 50, 175, "predator", 50, 10, Color(0.4, 0.38, 0.4), Color(0.8, 0.25, 0.15), 0, {"leg_len": 0.8, "neck": 0.5, "snout": 0.3, "wings": 1.6, "herd": true}],
	"hoplorhino": ["heavy", "hoplorhino", 88, 28, 190, "predator", 130, 14, Color(0.55, 0.45, 0.3), Color(0.8, 0.65, 0.3), 1, {"horns": 1, "shell": 0.6}],
	"mantis": ["insect", "giant mantis", 80, 30, 120, "predator", 40, 10, Color(0.4, 0.65, 0.25), Color(0.75, 0.85, 0.35), 0, {"neck": 0.6, "legs": 4}],
	"drakaina": ["serpent", "drakaina serpent", 62, 26, 60, "predator", 45, 10, Color(0.18, 0.32, 0.2), Color(0.7, 0.55, 0.2), 1, {"crest": true}],
	"scarab": ["shell", "horned scarab", 54, 22, 60, "grazer", 40, 6, Color(0.15, 0.4, 0.35), Color(0.4, 0.8, 0.6), 0, {"legs": 6, "horns": 1, "splay": true}],
	"rhinobeetle": ["shell", "rhinoceros beetle", 58, 24, 60, "grazer", 45, 9, Color(0.12, 0.1, 0.1), Color(0.35, 0.25, 0.15), 0, {"legs": 6, "horns": 1, "splay": true}],
	"pillbug": ["shell", "mushroom pillbug", 48, 16, 16, "slow", 50, 0, Color(0.45, 0.45, 0.48), Color(0.85, 0.3, 0.2), 2, {"legs": 6, "cap": 0.6}],
	"leafbug": ["insect", "leaf bug", 46, 20, 20, "slow", 30, 0, Color(0.35, 0.6, 0.2), Color(0.6, 0.8, 0.3), 1, {"shell": 0.5}],
	"moth": ["flyer", "peacock moth", 52, 30, 30, "drift", 8, 0, Color(0.5, 0.35, 0.25), Color(0.3, 0.5, 0.9), 2, {"wings": 1.8, "alt": 1.6}],
	"firefly": ["flyer", "firefly", 20, 30, 30, "drift", 4, 0, Color(0.2, 0.2, 0.15), Color(1.0, 0.95, 0.4), 0, {"wings": 0.8, "alt": 1.4, "glow": 2.0, "herd": true}],
	"dragonfly": ["flyer", "dragonfly", 40, 60, 60, "drift", 6, 0, Color(0.2, 0.45, 0.7), Color(0.6, 0.85, 0.9), 0, {"wings": 1.5, "alt": 1.2}],
	"spider": ["insect", "giant spider", 50, 30, 140, "predator", 30, 8, Color(0.12, 0.1, 0.1), Color(0.6, 0.15, 0.1), 2, {"legs": 8, "tail": 0.0, "body": Vector3(0.6, 0.45, 0.9)}],
	"centipede": ["grub", "giant centipede", 40, 30, 120, "predator", 35, 8, Color(0.55, 0.15, 0.08), Color(0.85, 0.55, 0.2), 1, {"legs": 6, "leg_len": 0.2, "splay": true, "body": Vector3(0.35, 0.25, 2.4)}],
	"phasma": ["insect", "stick phasma", 70, 15, 40, "grazer", 25, 0, Color(0.45, 0.35, 0.2), Color(0.55, 0.45, 0.25), 0, {"body": Vector3(0.15, 0.15, 1.8), "leg_len": 0.9}],
	"mykospider": ["insect", "myko spider", 60, 25, 130, "predator", 40, 9, Color(0.9, 0.88, 0.82), Color(0.8, 0.3, 0.2), 2, {"legs": 8, "cap": 0.7}],
	"grub": ["grub", "grub", 36, 12, 12, "grazer", 25, 0, Color(0.9, 0.85, 0.7), Color(0.75, 0.6, 0.45), 1, {}],
	# Ice worlds ("ic").
	"icestag": ["hoof", "ice stag", 120, 44, 175, "grazer", 45, 9, Color(0.78, 0.85, 0.92), Color(0.5, 0.75, 1.0), 0, {"antlers": 1.3, "glow": 0.6, "herd": true}],
	"shardcrawler": ["shell", "shard crawler", 40, 20, 60, "grazer", 40, 0, Color(0.6, 0.75, 0.9), Color(0.85, 0.95, 1.0), 2, {"legs": 6, "crest": true}],
	"icehare": ["small", "ice hare", 34, 50, 210, "skittish", 10, 0, Color(0.95, 0.96, 0.98), Color(0.75, 0.82, 0.9), 0, {"ears": 0.5}],
	"starcrawler": ["insect", "star crawler", 36, 25, 60, "grazer", 30, 0, Color(0.2, 0.3, 0.55), Color(0.6, 0.85, 1.0), 2, {"glow": 1.0}],
	"frostray": ["flyer", "frost ray", 48, 0, 120, "soar", 25, 0, Color(0.7, 0.82, 0.95), Color(0.95, 0.98, 1.0), 0, {"wings": 2.4, "alt": 4.0}],
	"wisp": ["drift", "ice wisp", 40, 14, 30, "drift", 10, 0, Color(0.7, 0.95, 1.0), Color(0.9, 1.0, 1.0), 0, {"glow": 2.0, "herd": true}],
	"frostbeast": ["heavy", "frost beast", 140, 22, 140, "predator", 220, 20, Color(0.9, 0.92, 0.95), Color(0.55, 0.65, 0.75), 0, {"horns": 2, "leg_len": 0.9, "monster": true}],
	"frostwolf": ["canine", "frost wolf", 70, 45, 170, "predator", 50, 10, Color(0.88, 0.92, 0.96), Color(0.6, 0.7, 0.85), 0, {"ears": 0.2, "herd": true}],
	"strider": ["insect", "ice strider", 110, 35, 90, "grazer", 40, 0, Color(0.6, 0.7, 0.8), Color(0.3, 0.4, 0.55), 0, {"legs": 4, "leg_len": 1.6, "splay": false}],
	"scuttler": ["insect", "scuttler", 36, 30, 150, "skittish", 15, 0, Color(0.4, 0.5, 0.6), Color(0.8, 0.85, 0.9), 2, {"legs": 6}],
	"bubblespider": ["insect", "bubble spider", 50, 25, 120, "predator", 35, 8, Color(0.55, 0.75, 0.9), Color(0.9, 0.95, 1.0), 2, {"legs": 8, "glow": 0.5}],
	"icewyrm": ["serpent", "ice wyrm", 80, 26, 80, "predator", 90, 14, Color(0.75, 0.85, 0.95), Color(0.4, 0.55, 0.8), 1, {"crest": true, "horns": 2}],
	# Volcanic worlds ("vo"): fierce.
	"magmabehemoth": ["heavy", "magma behemoth", 180, 20, 110, "predator", 400, 28, Color(0.15, 0.12, 0.12), Color(1.0, 0.4, 0.1), 1, {"glow": 1.5, "horns": 2, "monster": true}],
	"cinderstalker": ["canine", "cinder stalker", 80, 45, 180, "predator", 90, 14, Color(0.2, 0.15, 0.13), Color(1.0, 0.5, 0.15), 1, {"glow": 0.8}],
	"obsidianmantis": ["insect", "obsidian mantis", 90, 30, 130, "predator", 80, 16, Color(0.08, 0.08, 0.1), Color(0.9, 0.3, 0.1), 0, {"neck": 0.6, "legs": 4, "glow": 0.5}],
	"bloater": ["drift", "ash bloater", 70, 10, 20, "drift", 40, 0, Color(0.35, 0.3, 0.28), Color(1.0, 0.55, 0.2), 2, {"glow": 0.8}],
	"lavaserpent": ["serpent", "lava serpent", 70, 26, 70, "predator", 100, 16, Color(0.15, 0.1, 0.08), Color(1.0, 0.45, 0.1), 1, {"glow": 1.5, "crest": true}],
	"ventcrab": ["shell", "vent crab", 50, 22, 80, "grazer", 70, 10, Color(0.45, 0.2, 0.12), Color(0.9, 0.5, 0.2), 0, {"legs": 6, "splay": true}],
	"pyrohound": ["canine", "pyrohound", 70, 50, 190, "predator", 80, 13, Color(0.2, 0.12, 0.1), Color(1.0, 0.35, 0.1), 1, {"glow": 1.0, "herd": true, "ears": 0.2}],
	"ashwraith": ["drift", "ash wraith", 110, 20, 60, "predator", 70, 12, Color(0.2, 0.2, 0.22), Color(0.9, 0.5, 0.3), 2, {"glow": 0.6}],
	"basaltgolem": ["heavy", "basalt golem", 210, 20, 120, "predator", 480, 32, Color(0.18, 0.17, 0.18), Color(1.0, 0.45, 0.15), 1, {"glow": 1.0, "monster": true, "leg_len": 0.9}],
	"emberqueen": ["flyer", "ember swarm queen", 160, 44, 210, "predator", 200, 12, Color(0.25, 0.12, 0.08), Color(1.0, 0.6, 0.2), 0, {"wings": 3.0, "alt": 3.0, "glow": 1.5, "monster": true}],
	"cratermaw": ["grub", "crater maw", 140, 22, 110, "predator", 160, 18, Color(0.3, 0.22, 0.18), Color(1.0, 0.4, 0.15), 1, {"glow": 0.8, "monster": true}],
	"fumaroletitan": ["heavy", "fumarole titan", 220, 22, 165, "predator", 560, 36, Color(0.22, 0.2, 0.2), Color(1.0, 0.55, 0.2), 1, {"glow": 1.2, "horns": 2, "monster": true}],
}
const SETS := {
	"fo": ["goat", "sheep", "deer", "donkey", "hare", "fox", "tortoise", "owl", "eagle", "wolf", "boar", "snake", "tigrokeros", "mykelephas",
		"selas", "capslug", "toad", "pangolin", "aeromanta", "jelly", "harpyx", "hoplorhino", "mantis", "drakaina", "scarab", "rhinobeetle",
		"pillbug", "leafbug", "moth", "firefly", "dragonfly", "spider", "centipede", "phasma", "mykospider", "grub"],
	"ic": ["icestag", "shardcrawler", "icehare", "starcrawler", "frostray", "wisp", "frostbeast", "frostwolf", "strider", "scuttler", "bubblespider", "icewyrm"],
	"vo": ["magmabehemoth", "cinderstalker", "obsidianmantis", "bloater", "lavaserpent", "ventcrab", "pyrohound", "ashwraith", "basaltgolem", "emberqueen", "cratermaw", "fumaroletitan"]}
## The 2D game's tempers -> the 3D creature's (how it behaves).
const TEMPERS := {"grazer": "grazer", "skittish": "skittish", "predator": "predator", "slow": "grazer", "bird": "skittish", "soar": "skittish", "drift": "grazer"}


## One of the 2D game's species, built for CosmosCreature.
static func species(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var sp: Array = SPECIES[id]
	var k: Dictionary = (PLANS[sp[0]] as Dictionary).duplicate()
	k.merge(sp[11], true)
	var b: Vector3 = k["body"]
	var height_m := float(sp[2]) / 55.0
	var size := height_m / maxf(float(k["leg_len"]) + b.y + float(k.get("alt", 0.0)) * 0.0, 0.3)
	var mon := bool(k.get("monster", false))
	k.merge({"name": sp[1], "id": id, "temper": TEMPERS.get(sp[5], "grazer"), "temper2d": sp[5], "size": size, "monster": mon,
		"horns": int(k.get("horns", 0)), "crest": bool(k.get("crest", false)),
		"c1": sp[8], "c2": sp[9], "pattern": sp[10], "eyes": (sp[9] as Color) if float(k.get("glow", 0.0)) > 0.0 else Color(0.1, 0.08, 0.05),
		"walk": maxf(float(sp[3]) / 30.0, 0.3), "run": maxf(float(sp[4]) / 30.0, 0.4), "hp": float(sp[6]), "bite": float(sp[7]),
		"scale": 1.0, "herd": bool(k.get("herd", false)) or (sp[5] == "grazer" and rng.randf() < 0.4)}, true)
	return k


## Which of the 2D game's sets live on a planet of this type.
static func set_of(type: String, shape: PlanetShape) -> String:
	match type:
		"ocean", "thalassa":
			return "fo"
		"ice", "krystallos":
			return "ic"
		"volcanic", "akrotiri":
			return "vo"
	if shape.sea == 1:
		return "fo"
	if shape.sea == 2:
		return "ic"
	if shape.sea == 3:
		return "vo"
	return ""


static func design(shape: PlanetShape, seed: int, type: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 97 + 11
	# The 2D game's animals where it had them: a few species of the planet's
	# set, at least one hunter among them.
	var set := set_of(type, shape)
	if set != "":
		var pool: Array = (SETS[set] as Array).duplicate()
		var pick: Array = []
		var want := 7 if set == "fo" else 5
		while pick.size() < want and not pool.is_empty():
			pick.append(pool.pop_at(rng.randi() % pool.size()))
		if not pick.any(func(i): return str(SPECIES[i][5]) == "predator"):
			for i in pool:
				if str(SPECIES[i][5]) == "predator":
					pick[pick.size() - 1] = i
					break
		var out: Array = []
		for i in pick:
			out.append(species(i, rng))
		return out
	var n: int = COUNT_BY_TYPE.get(type, 2)
	var L := shape.look
	var base: Color = L.get("land_mid", Color(0.5, 0.45, 0.35))
	var out: Array = []
	for i in n:
		var temper := "grazer"
		if i == n - 1 and n > 1:
			temper = "predator"
		elif i == 1:
			temper = "skittish"
		elif n == 1:
			temper = "predator" if rng.randf() < 0.5 else "grazer"
		var legs: int = [4, 4, 2, 6, 0][rng.randi() % 5] if temper != "skittish" else [2, 4][rng.randi() % 2]
		var size := rng.randf_range(0.6, 1.4)
		if temper == "predator":
			size = rng.randf_range(1.2, 2.0)
		var monster := temper == "predator" and rng.randf() < 0.55
		var c1 := Color.from_hsv(fmod(base.h + rng.randf_range(-0.15, 0.15) + (0.5 if rng.randf() < 0.3 else 0.0), 1.0),
			clampf(base.s + rng.randf_range(-0.2, 0.3), 0.15, 0.85), rng.randf_range(0.35, 0.8))
		var c2 := Color.from_hsv(fmod(c1.h + rng.randf_range(0.05, 0.5), 1.0), rng.randf_range(0.2, 0.9), rng.randf_range(0.2, 0.95))
		if temper == "predator":
			c1 = c1.darkened(0.25)
		var name := ""
		for k in rng.randi_range(2, 3):
			name += SYL[rng.randi() % SYL.size()]
		name = (name + TAILS[rng.randi() % TAILS.size()]).capitalize()
		out.append({
			"name": name, "temper": temper, "legs": legs, "size": size, "monster": monster,
			"body": Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.45, 0.8), rng.randf_range(1.0, 1.8)),
			"leg_len": rng.randf_range(0.5, 1.1) if legs > 0 else 0.0,
			"leg_w": rng.randf_range(0.1, 0.2),
			"neck": rng.randf_range(0.0, 1.0) if legs != 2 else rng.randf_range(0.2, 0.6),
			"head": rng.randf_range(0.28, 0.5),
			"snout": rng.randf_range(0.0, 0.6),
			"tail": rng.randf_range(0.0, 1.4),
			"horns": rng.randi_range(0, 2) if rng.randf() < 0.5 else 0,
			"crest": rng.randf() < 0.3,
			"c1": c1, "c2": c2, "pattern": rng.randi() % 3, "eyes": Color.from_hsv(rng.randf(), 0.8, 1.0),
			"walk": rng.randf_range(1.4, 2.6) * size, "run": rng.randf_range(5.0, 8.5) * (1.0 if temper != "predator" else 0.85) * sqrt(size),
			"hp": (40.0 if temper != "predator" else 90.0) * size * (2.5 if monster else 1.0),
			"bite": 9.0 * size * (1.8 if monster else 1.0),
			"scale": rng.randf_range(2.6, 3.6) if monster else 1.0,
			"herd": temper == "grazer" and rng.randf() < 0.7,
		})
	return out


static func label(kind: Dictionary) -> String:
	if kind.has("id"):
		return str(kind["name"]).capitalize()
	var t: String = {"grazer": "grazer", "skittish": "skittish", "predator": "predator"}[kind["temper"]]
	return "%s (%s)" % [kind["name"], "monster" if kind["monster"] else t]
