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


static func design(shape: PlanetShape, seed: int, type: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 97 + 11
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
	var t: String = {"grazer": "grazer", "skittish": "skittish", "predator": "predator"}[kind["temper"]]
	return "%s (%s)" % [kind["name"], "monster" if kind["monster"] else t]
