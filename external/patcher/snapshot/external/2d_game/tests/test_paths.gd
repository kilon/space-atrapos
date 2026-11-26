extends TestCase
## Walking on every planet: random walks anywhere within the path grid that
## have a way there arrive - round cliffs and up ramps, through doorways, and
## on past the grid's window when the way round leaves it (PlanetSurface._walk_to).

const DT := 1.0 / 60.0

func _surface(pid: String) -> Node:
	SaveGame.landed_planet = pid
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	s.set_process(false)
	for c in s.creatures:
		c.queue_free()
	s.creatures.clear()
	s._fauna_plans.clear()
	return s


func _walks(pid: String) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var s: Node = await _surface(pid)
	var c: Vector2 = s.lander.position
	var n := 0
	var fails := []
	var tries := 0
	while n < 40 and tries < 4000:
		tries += 1
		var a := c + Vector2(rng.randf_range(-2500, 2500), rng.randf_range(-1300, 1300))
		var z := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(150, 1200)
		if not s.walkable_at(a, 10.0) or not s.walkable_at(z, 10.0) or not s.in_nav(a, 4) or not s.in_nav(z, 4):
			continue
		var p: PackedVector2Array = s.find_path(a, z)
		if p.is_empty():
			continue
		n += 1
		s.pilot.position = a
		s._walk_to(z)
		var t := 0.0
		var doors: Array = s.all_doors()
		var steps := 0
		while t < 60.0 and (s.pilot.moving or s._far_goal != Vector2.INF):
			s._process(DT)
			for d in doors:
				d._process(DT)
			t += DT
			steps += 1
			if steps % 20 == 0:
				await tree.process_frame   # (the path grid's worker gets real time)
		var end: Vector2 = s.pilot.position
		if end.distance_to(z) > 20.0:
			fails.append("%s -> %s ended %s (%.0f px short, %s, path %d pts, moving %s)" % [a.round(), z.round(), end.round(), end.distance_to(z), "%.1fs" % t, p.size(), s.pilot.moving])
	for f in fails:
		print(pid, ": ", f)
	check(fails.is_empty(), "%s: %d of %d walks didn't arrive" % [pid, fails.size(), n])
	s.queue_free()
	await tree.process_frame


func test_krystallos_walks() -> void:
	await _walks("krystallos")


func test_selene_walks() -> void:
	await _walks("selene")


func test_thalassa_walks() -> void:
	await _walks("thalassa")


func test_kronos_walks() -> void:
	await _walks("kronos")
