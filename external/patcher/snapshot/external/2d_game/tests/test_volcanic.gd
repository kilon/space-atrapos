extends TestCase
## Akrotiri, the volcanic planet in the home system: landable, built from the
## volcanic terrain tile set ("vo": basalt, ash, sulphur - magma for water).

var _old_planet := ""

func setup() -> void:
	_old_planet = SaveGame.landed_planet


func teardown() -> void:
	SaveGame.landed_planet = _old_planet


func test_akrotiri_is_volcanic_and_landable() -> void:
	var pd: Dictionary = Planets.PLANETS["akrotiri"]
	check(pd["landable"] and pd["tiles"] == "vo" and pd["template"] == "inferno", "a landable lava world")
	check(Planets.PLANETS.keys().any(func(k): return k == "akrotiri"), "in the home system")
	check(load("res://scripts/main.gd").HOME_ORBITS.any(func(o): return o[0] == "akrotiri"), "orbiting the home star")
	var tt := preload("res://scripts/terrain_tiles.gd")
	for n in tt.ground_pieces("vo"):
		if not n.substr(3) in tt.RIMS:   # (rims are made, not cut)
			check(ProcArt.has_sprite("tile_" + n), "the piece %s is cut" % n)
	for role in ["trees", "shrubs", "rocks", "ruins"]:
		for n in preload("res://scripts/terrain_tiles.gd").SETS["vo"][role]:
			check(ProcArt.has_sprite("tile_vo_" + n), "the %s %s is cut" % [role, n])


func test_landing_on_akrotiri() -> void:
	SaveGame.landed_planet = "akrotiri"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	await s.stream_all()   # (the whole planet in: it streams, a chunk at a time)
	s.set_process(false)
	check(s.walkable_at(s.pilot.position), "you stand on solid ground")
	# Magma (the first terrain band, unwalkable): there is some, and you can't walk on it.
	var magma := 0
	var stood := 0
	var n: int = s.N
	for k in range(0, n * n, 13):
		if s._terrain[k] == 0:
			magma += 1
			if s.walkable_at(s._cell_pos(Vector2i(k / n, k % n))):
				stood += 1
	check(magma > 20, "rivers of magma (%d sampled cells)" % magma)
	check_eq(stood, 0, "nobody walks on magma")
	check(s.pdata["tiles"] == "vo", "built from the volcanic tile set")
	check(s.buildings.is_empty() and s._plans.is_empty(), "no buildings anywhere on it")
	check(s.npcs.all(func(n): return n.species == "pirate"), "no citizens - only pirates roam")
	# Its wildlife: the volcanic beasts, every one a predator.
	var kinds := SurfaceCreature.FAUNA["vo"].map(func(r): return r[0])
	check(s._fauna_plans.size() > 30, "beasts across the planet (%d)" % s._fauna_plans.size())
	check(s._fauna_plans.all(func(f): return f["species"] in kinds), "only volcanic beasts")
	for k in kinds:
		check(SurfaceCreature.SPECIES[k]["temper"] == "predator", "the %s is a predator" % k)
		check(SurfaceCreature.SPECIES[k]["h"] >= 130.0, "the %s is big (taller than you)" % k)
	s.queue_free()
	await tree.process_frame


## Volcanic beasts have 4 times the health and double the damage of the
## creatures they're modelled on (SurfaceCreature.FIERCE_HP / FIERCE, "like").
func test_volcanic_beasts_are_tougher() -> void:
	check_eq(SurfaceCreature.FIERCE_HP, 4.0, "four times the health")
	check_eq(SurfaceCreature.FIERCE, 2.0, "twice the bite")
	for row in SurfaceCreature.FAUNA["vo"]:
		var sp: Dictionary = SurfaceCreature.SPECIES[row[0]]
		check(sp.has("like") and SurfaceCreature.SPECIES.has(sp["like"]), "%s is modelled on a normal creature" % row[0])
		var base: Dictionary = SurfaceCreature.SPECIES[sp["like"]]
		check_eq(sp["hp"], base["hp"] * 4.0, "%s: four times the %s's health" % [row[0], sp["like"]])
		check_eq(sp["bite"], base["bite"] * 2.0, "%s: double the %s's damage" % [row[0], sp["like"]])


## A predator in reach bites - even standing away from its own side of you
## (it used to freeze in its attack pose, trying to get round to that side).
func test_a_beast_in_reach_bites() -> void:
	SaveGame.landed_planet = "akrotiri"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	s.set_process(false)
	for c in s.creatures.duplicate():
		c.queue_free()
	await tree.process_frame
	for kind in ["ventcrab", "cinderstalker"]:
		var c := SurfaceCreature.make(kind, "vo")
		c.surface = s
		s.objects.add_child(c)
		await tree.process_frame
		c._side = Vector2.RIGHT
		c.position = s.pilot.position - Vector2.RIGHT * c._reach() * 0.7   # (in reach, on the far side from its spot)
		c._threat = s.pilot
		c._cd = 0.0
		c._go("chase")
		s.pilot.hp = s.pilot.max_hp
		s.pilot.shield = s.pilot.max_shield
		c._fight(1.0 / 60.0)
		check(s.pilot.hp + s.pilot.shield < s.pilot.max_hp + s.pilot.max_shield, "%s: in reach, it bites at once" % kind)
		c.queue_free()
	s.queue_free()
	await tree.process_frame


## A planet's environment on foot (Planets.environment): volcanic heat halves
## your health's regeneration; ice slows your walking by 20%.
func test_environments() -> void:
	check_eq(Planets.environment("akrotiri")["regen"], 0.5, "Akrotiri: health regenerates at half the rate")
	check_eq(Planets.environment("krystallos")["speed"], 0.8, "Ida: you walk 20% slower")
	check_eq(Planets.environment("selene")["speed"], 0.8, "Kamares too (ice)")
	var forest: Dictionary = Planets.environment("thalassa")
	check(forest["regen"] == 1.0 and forest["speed"] == 1.0, "Amnissos: as ever")
	for pid in ["akrotiri", "krystallos", "thalassa"]:
		SaveGame.landed_planet = pid
		var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
		tree.root.add_child(s)
		while not s.is_built:
			await tree.process_frame
		var env: Dictionary = Planets.environment(pid)
		var p: Node2D = s.pilot
		check(is_equal_approx(p.speed, p.SPEED * env["speed"]), "%s: walking at %.0f px/s" % [pid, p.speed])
		# Hurt, out of the fight for a while: health comes back at the planet's rate.
		s.set_process(false)
		p.hp = 50.0
		p._since_hit = 99.0
		p._process(1.0)
		check(is_equal_approx(p.hp, 50.0 + p.REGEN * env["regen"]), "%s: %.1f health back in a second" % [pid, p.hp - 50.0])
		s.queue_free()
		await tree.process_frame
