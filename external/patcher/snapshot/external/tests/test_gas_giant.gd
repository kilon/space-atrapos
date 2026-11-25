extends TestCase
## Dikte, the gas giant: landable, built from the platform tile set ("gg") -
## every platform at level 1 or more with its underside toward the open sky,
## bridges between the platforms, no villages but industrial sites, a cloud
## sky behind, and everything reachable from the pad.

var _old := ""


func setup() -> void:
	_old = SaveGame.landed_planet


func teardown() -> void:
	SaveGame.landed_planet = _old
	Ground3D.enabled = true


func test_kronos_platforms() -> void:
	Ground3D.enabled = false      # (the 2D ground: its tile layers and pictures - the fallback)
	for n in ["deck", "block_corner", "rail_left", "fuel_tank", "robot", "deck_b", "crane_b"]:
		check(ProcArt.has_sprite("tile_gg_" + n), "sprite tile_gg_%s" % n)
	check(Planets.PLANETS["kronos"]["landable"], "Dikte is landable")
	SaveGame.landed_planet = "kronos"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	await s.stream_all()   # (the whole planet in: it streams, a chunk at a time)
	check(s._sky, "its water is open sky")
	var N: int = s.N
	var land := 0
	var low := 0
	var sky_edges := 0
	for i in range(1, N - 1):
		for j in range(1, N - 1):
			var k: int = i * N + j
			if s._walk_t[s._terrain[k]] == 0:
				continue
			land += 1
			if int(s._lvl[k]) < 1:
				low += 1
			if s._walk_t[s._terrain[k + N]] == 0 or s._walk_t[s._terrain[k + 1]] == 0:
				sky_edges += 1
	check(land > N * N * 0.15 and land < N * N * 0.75, "platforms with sky between (%d%% land)" % (land * 100 / (N * N)))
	check(low == 0, "every platform tile is at level 1 or more (%d at 0)" % low)
	check(sky_edges > 200, "platform edges over the sky (%d)" % sky_edges)
	# An edge tile over the sky draws the platform's underside (a block piece), not a shore.
	var ids := []
	for r in ["block_corner", "block_left", "block_right"]:
		ids.append(s._tile_pieces.find(s.TTILES.pc("gg", r)))
	var faces := 0
	for layer in s.tile_ground.get_children():
		if layer is TileMapLayer:
			for id in ids:
				faces += layer.get_used_cells_by_id(id).size()
	check(faces > sky_edges / 2, "undersides drawn toward the sky (%d)" % faces)
	check(s._plans.is_empty() and s.buildings.is_empty(), "no villages")
	check(s._industry.size() >= 6, "industrial sites planned (%d)" % s._industry.size())
	for site in s._industry:
		var c: Vector2i = site["cell"]
		check(s._plot_cells.has(c) and s.walkable_at(s._cell_pos(c)), "%s on a flat plot" % site["kind"])
	var deck: Node = s.find_child("GasSky", true, false)
	check(deck != null and deck is GasSky, "the painted cloud deck behind")
	for i in 6:
		check(ProcArt.has_sprite("sky_gg_band%d" % (i + 1)), "band %d" % (i + 1))
	for n in ["storm_red", "eddy_cream", "festoon_brown", "ovals_three"]:
		check(ProcArt.has_sprite("sky_gg_" + n), "storm " + n)
	if deck is GasSky:
		var before: float = deck._scroll[1]
		deck._process(1.0)
		check(absf(deck._scroll[1] - before) > 5.0 and signf(deck._scroll[1] - before) != signf(GasSky.WINDS[0]), "the bands scroll, belts against zones")
		check(deck._storms.size() >= 10, "storms drift on the bands (%d)" % deck._storms.size())
		# Each band wraps without a seam: its left and right columns match.
		var img: Image = ProcArt.get_image("sky_gg_band2")
		var diff := 0.0
		for y in range(0, img.get_height(), 7):
			var a: Color = img.get_pixel(0, y)
			var b: Color = img.get_pixel(img.get_width() - 1, y)
			diff += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
		diff /= ceili(img.get_height() / 7.0)
		check(diff < 0.25, "a band's ends meet (mean difference %.2f)" % diff)
	# Reachable: a far platform walked to leg by leg (bridges).
	var far := Vector2.INF
	for site in s._industry:
		var p: Vector2 = s._cell_pos(site["cell"])
		if far == Vector2.INF or p.distance_to(s.pilot.position) > far.distance_to(s.pilot.position):
			far = p
	var path: PackedVector2Array = s.find_path(s.pilot.position, s._nearest_walkable(far))
	check(not path.is_empty() or not s.in_nav(far), "a way toward the farthest site")
	s.queue_free()
