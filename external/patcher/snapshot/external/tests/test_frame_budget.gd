extends TestCase
## What keeps the game at 240 FPS (see tools/fps_test.py - the real measure,
## in a window): the mechanisms checked here headless, so that breaking one
## fails the test suite - batching (the ground's and the buildings' pieces
## in shared atlases), the ground drawn as pictures (GroundChunks), far
## culling, throttled redraws - and a loose per-frame script budget on a
## planet and in a space battle (catches a big slowdown; headless and 12 at a
## time, timings are rough - the budget is several times what they take).

const TTILES := preload("res://scripts/terrain_tiles.gd")
## The scripts' time a frame on a planet / in a battle may take (ms): about
## 1 ms when it was set (1.5 under the test suite's load) - a 4 ms budget
## leaves room for noise and catches a real slowdown.
const BUDGET_MS := 4.0

var _old_planet := ""


func setup() -> void:
	_old_planet = SaveGame.landed_planet


func teardown() -> void:
	SaveGame.landed_planet = _old_planet
	Ground3D.enabled = true


## The scripts' time a frame (ms) under `root`: every processing node's
## _process called for `n` frames of 1/60 s, timed (headless frames are
## paced, so the frame time says nothing; this is the scripts' own work).
func _frame_ms(root: Node, n: int) -> float:
	var nodes := root.find_children("*", "", true, false).filter(func(x): return x.is_processing() and x.has_method("_process"))
	if root.is_processing() and root.has_method("_process"):
		nodes.push_front(root)
	var t0 := Time.get_ticks_usec()
	for i in n:
		for x in nodes:
			if is_instance_valid(x) and x.is_inside_tree() and not x.is_queued_for_deletion():
				x._process(1.0 / 60.0)
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


func _surface(pid: String) -> Node:
	SaveGame.landed_planet = pid
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	# (the planet streams on round you after it's built: measured once it's all in)
	var t0 := Time.get_ticks_msec()
	while not s.streaming_idle() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return s


## Every piece of a planet's ground in one texture: Godot draws runs of the
## same texture in one draw call (a texture each was ~550 draw calls).
func test_ground_tiles_share_one_texture() -> void:
	var names: Array = TTILES.ground_pieces("fo")
	var ts: TileSet = TTILES.tile_set(names)
	var rids := {}
	var padded := 0
	for i in ts.get_source_count():
		var src := ts.get_source(ts.get_source_id(i)) as TileSetAtlasSource
		if src and src.texture:
			rids[src.texture.get_rid()] = true
			if src.use_texture_padding:
				padded += 1
	check(names.size() > 10, "the forest ground has its pieces (%d)" % names.size())
	check_eq(rids.size(), 1, "all of them in one atlas texture")
	check_eq(padded, 0, "no source makes its own padded copy (that's a texture each again)")


## Walls, floors, roofs and the sprite pieces of the buildings: regions of one atlas.
func test_building_textures_share_one_atlas() -> void:
	if not MinoanTiles.available():
		return
	var texs: Array = [MinoanTiles.wall("x", "plain", 0), MinoanTiles.wall("y", "window", 1),
		MinoanTiles.floor_tile("minoan", 0), MinoanTiles.roof_tile(1)]
	var st: Dictionary = MinoanTiles.style("palace")
	texs.append(MinoanTiles.texture(st["column"]))
	var atlases := {}
	for t in texs:
		check(t is AtlasTexture, "%s is a region of the atlas" % t)
		if t is AtlasTexture:
			atlases[(t as AtlasTexture).atlas.get_rid()] = true
	check_eq(atlases.size(), 1, "one atlas for them all")


## A tiled planet's ground is drawn as pictures of it (GroundChunks): the
## tile layers live in a world of their own; squares near the view are rendered.
func test_planet_ground_drawn_as_pictures() -> void:
	Ground3D.enabled = false      # (the 2D ground: its tile layers and pictures - the fallback)
	var s: Node = await _surface("thalassa")
	check(s.ground_chunks != null and s.tile_ground != null, "the ground has its pictures")
	if s.ground_chunks:
		check(s.tile_ground.get_viewport() != s.get_viewport(), "its tiles aren't in the game's own world")
		var v := Rect2(s.pilot.position - Vector2(960, 540), Vector2(1920, 1080))
		s.ground_chunks.update(v, true)
		check(s.ground_chunks.chunk_count() >= 4, "the squares round the view rendered (%d)" % s.ground_chunks.chunk_count())
		var n: int = s.ground_chunks.chunk_count()
		s.ground_chunks.update(v)
		check_eq(s.ground_chunks.chunk_count(), n, "the same view: nothing rendered again")
	s.queue_free()
	await tree.process_frame


## What's far off screen isn't gathered for drawing (FAR_LAYER), what's in view is.
func test_far_culling() -> void:
	var s: Node = await _surface("thalassa")
	s.view_rect = Rect2(s.pilot.position - Vector2(1200, 800), Vector2(2400, 1600))
	s._cull_at = 0   # (it runs CULL_HZ times a second: due now)
	s._cull_far()
	var near := 0
	var far := 0
	var wrong := 0
	var vr: Rect2 = s.view_rect
	for c in s.objects.find_children("*", "Node2D", true, false):
		if c.visibility_layer == s.FAR_LAYER:
			far += 1
			if vr.has_point(c.global_position):
				wrong += 1
		elif vr.has_point(c.global_position):
			near += 1
	check(far > 100, "pieces far off are culled (%d)" % far)
	check(near > 50, "what's in view isn't (%d)" % near)
	check_eq(wrong, 0, "nothing in view culled")
	check(s.get_viewport().canvas_cull_mask & s.FAR_LAYER == 0, "the viewport doesn't draw the far layer")
	var far_layer: int = s.FAR_LAYER
	s.queue_free()
	await tree.process_frame
	check(tree.root.canvas_cull_mask & far_layer != 0, "and draws it again once the planet's gone")


## Animated pictures that don't need every frame: at most `hz` redraws a second.
func test_redraws_are_throttled() -> void:
	var ci := Node2D.new()
	tree.root.add_child(ci)
	var n := 0
	var t0 := Time.get_ticks_usec()
	while Time.get_ticks_usec() - t0 < 100000:   # 0.1 s of asking
		if UI.redraw_due(ci, 60.0):
			n += 1
		OS.delay_usec(500)
	check(n >= 5 and n <= 8, "60 a second: 6 or so in 0.1 s (%d)" % n)
	ci.hide()
	check(not UI.redraw_due(ci, 1000.0), "never while hidden")
	ci.queue_free()


## A loose budget for a planet's scripts each frame (animals, people, the
## surface): several times what it takes - a big slowdown fails here.
func test_planet_frame_budget() -> void:
	var s: Node = await _surface("thalassa")
	for i in 30:
		await tree.process_frame
	var ms := _frame_ms(s, 60)
	check_lt(ms, BUDGET_MS, "Amnissos: the scripts' time a frame (%.2f ms; ~1 when it was set)" % ms)
	s.queue_free()
	await tree.process_frame


## The same for a battle in space: six pirates, you fighting back.
func test_battle_frame_budget() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false
	var main: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(main)
	for i in 40:
		await tree.process_frame
	main.ship.invulnerable = true
	var foes := []
	for k in 6:
		foes.append(main.spawn_enemy(main.ship.global_position + Vector2.from_angle(k * TAU / 6.0) * 700.0))
	main.ship.set_attack_target(foes[0], true)
	for i in 30:
		await tree.process_frame
	var ms := _frame_ms(main, 60)
	check_lt(ms, BUDGET_MS, "a battle: the scripts' time a frame (%.2f ms; ~1 when it was set)" % ms)
	main.queue_free()
	await tree.process_frame
	Galaxy.new_game(false)
