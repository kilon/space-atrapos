extends TestCase
## The automaton's skills (Skills): the animations rendered from the 3D models
## (SheetPuppet's clip mode), levels and the Spell Book, martial arts, the
## leap, the arcana, pirates fighting hand to hand.

const DT := 1.0 / 60.0

var _old_planet := ""


class Dummy extends Node2D:
	var hits := 0
	var taken := 0.0
	var dead := false
	var staggered := 0.0
	var floored := false
	func surface_hit(d: float, _dtype := "") -> void:
		hits += 1
		taken += d
	func stagger(t: float, down := false) -> void:
		staggered = t
		floored = floored or down


func setup() -> void:
	_old_planet = SaveGame.landed_planet


func teardown() -> void:
	SaveGame.landed_planet = _old_planet
	SheetPuppet.classic = false
	SheetPuppet.model3d = true
	Ground3D.enabled = true
	Accuracy.sure = false


func _surface(pid := "thalassa") -> Node:
	SaveGame.landed_planet = pid
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	s.set_process(false)
	s.pilot.set_process(false)
	for n in s.npcs.duplicate():      # (an empty field: no one joins the fight)
		if n.species == "pirate":
			s.npcs.erase(n)
			n.queue_free()
	return s


func _foe(s: Node, at: Vector2) -> Dummy:
	var d := Dummy.new()
	d.add_to_group("surface_hostiles")
	d.position = at
	s.objects.add_child(d)
	return d


## The fight goes on for `t` s: the surface's fighting, the pilot, the spells in flight.
func _run(s: Node, t: float, also: Array = []) -> void:
	var left := t
	while left > 0.0:
		left -= DT
		s._update_attack(DT)
		s._update_tools(DT)
		s.pilot._process(DT)
		s.pilot.puppet._process(DT)
		for n in also:
			if is_instance_valid(n) and n.is_processing():
				n._process(DT)
				if n.get("puppet") != null:
					n.puppet._process(DT)
		for c in s.objects.get_children():
			if c is SkillFx.Fireball and not c.is_queued_for_deletion():
				c._process(DT)


func _all_ranks(s: Node, r := 5) -> void:
	var st: Dictionary = Skills.state(s.state["player"])
	for id in Skills.SKILLS:
		st["ranks"][id] = r
	s.pilot.stamina = Stamina.MAX


## The automaton and the pirate android: animations rendered from their 3D
## models, 8 views each, packed into atlas pages (the automaton's: when it
## isn't drawn as the model itself - "rendered sprites").
func test_clip_puppets() -> void:
	SheetPuppet.model3d = false
	for id in ["player", "pirate"]:
		check(SheetPuppet.has_clips(id), "%s has rendered clips" % id)
		var p := SheetPuppet.new()
		p.height = 128.0
		tree.root.add_child(p)
		p.setup(id)
		check(p.clip_mode, "%s: drawn from its clips" % id)
		var set_: Dictionary = SheetPuppet.clip_set(id)
		check(is_equal_approx(float(set_["fps"]), 30.0), "30 frames a second")
		check((set_["pages"] as Array).size() == int(set_["page_count"]) and int(set_["page_count"]) > 0, "its atlas pages are loaded (%d)" % int(set_["page_count"]))
		var need := ["guard", "walk", "jab", "cross", "hook", "uppercut", "front", "round", "hit", "block", "ko", "gun_idle", "gun_walk", "raise", "fire"]
		if id == "player":
			need += ["idle", "run", "gun_run", "elbow", "knee", "side", "spin", "sweep", "flykick", "palm", "leap", "cast_bolt", "cast_sky", "cast_dome", "cast_summon"]
		var frames := 0
		for c in need:
			if not check(set_["clips"].has(c), "%s: clip %s" % [id, c]):
				continue
			var cl: Dictionary = set_["clips"][c]
			for d in SheetPuppet.DIRS:
				var fr: Array = cl["frames"].get(d, [])
				if not check(fr.size() == int(cl["n"]) and fr.size() > 0, "%s %s: frames facing %s" % [id, c, d]):
					continue
				frames += fr.size()
				for f in [fr[0], fr[-1]]:
					var tex: Texture2D = set_["pages"][int(f[0])]
					check(f[1] >= 0 and f[2] >= 0 and f[1] + f[3] <= tex.get_width() and f[2] + f[4] <= tex.get_height(), "%s %s %s: inside its page" % [id, c, d])
		check(frames > 1500, "%s: %d frames in all" % [id, frames])
		# Standing, walking, the rifle coming up - from the same controls as the sheets.
		p._process(DT)
		check_eq(p.shown(), "gun_idle", "standing with the rifle")
		var h: float = p._sprite.region_rect.size.y * p._sprite.scale.y
		check(h > 110.0 and h < 140.0, "about 128 px tall on screen (%.0f)" % h)
		var views := {}
		for i in 8:
			p.set_facing(Vector2.from_angle(i * PI / 4.0))
			views[p._sprite.region_rect] = true
		check_eq(views.size(), 8, "a view of its own for each of the 8 directions")
		p.walk = 1.0
		var seen := {}
		for k in 30:
			p.phase = k / 30.0 * TAU
			p._process(DT)
			seen[p._fi] = true
		check_eq(p.shown(), "gun_walk", "walking with the rifle")
		check(seen.size() >= 28, "the walk cycle's frames by the distance walked (%d)" % seen.size())
		p.armed = false
		p._process(DT)
		check_eq(p.shown(), "walk", "and without it")
		p.walk = 0.0
		p.stance = "guard"
		p._process(DT)
		check_eq(p.shown(), "guard", "the fighting stance")
		p.raise_amt = 1.0
		p._process(DT)
		check_eq(p.shown(), "raise", "the rifle up")
		check(p.muzzle() != Vector2.ZERO and p.muzzle().y < -40.0, "the muzzle at chest height (%s)" % p.muzzle())
		p.raise_amt = 0.0
		# A clip played once: through its frames, then back to standing.
		check(p.play("jab"), "plays a blow")
		check(p.mark_time("jab", "hit") > 0.0 and p.mark_time("jab", "hit") < p.clip_time("jab"), "its hit mark is inside it")
		var t := 0.0
		while p.playing() != "" and t < 2.0:
			p._process(DT)
			t += DT
		check(absf(t - p.clip_time("jab")) < 0.06, "for as long as the clip is (%.2f s)" % t)
		check(p.play("ko", 1.0, true), "a fall, held on its last frame")
		for k in 60:
			p._process(DT)
		check(p.held() and p.shown() == "ko", "it stays down")
		p.stop()
		check(SheetPuppet.portrait(id) != null, "a portrait")
		p.queue_free()
	# The automaton leaves the ground in its leap.
	var a := SheetPuppet.new()
	tree.root.add_child(a)
	a.setup("player")
	a.play("leap")
	var top := 0.0
	for k in 60:
		a._process(DT)
		top = maxf(top, a.air())
	check(top > 40.0, "the leap: off the ground (%.0f px)" % top)
	a.gait = "run"
	check(a.stride_px() > 100.0, "a run's stride is longer (%.0f px)" % a.stride_px())
	a.queue_free()
	# The classic sheets are still there: the backup.
	SheetPuppet.classic = true
	var c2 := SheetPuppet.new()
	tree.root.add_child(c2)
	c2.setup("player")
	check(not c2.clip_mode and c2._sprite.texture.resource_path.contains("art/player/player_idle_"), "classic sprites: the hand-drawn sheets again")
	check(SheetPuppet.portrait("player").resource_path.contains("art/player/"), "and their portrait")
	c2.queue_free()
	SheetPuppet.classic = false


## The automaton as its actual 3D model, drawn live on the 3D stage (Stage3D).
func test_model_puppet() -> void:
	check(SheetPuppet.has_model("player"), "the automaton has a 3D model")
	check(not SheetPuppet.has_model("pirate"), "(the pirates: sprites rendered from theirs)")
	var info: Dictionary = Stage3D.info("player")
	SheetPuppet.model3d = false
	var set_: Dictionary = SheetPuppet.clip_set("player")
	SheetPuppet.model3d = true
	for c in set_["clips"]:
		if check(info["clips"].has(c), "the model has the clip %s" % c):
			check(int(info["clips"][c]["n"]) == int(set_["clips"][c]["n"]) and info["clips"][c]["marks"] == set_["clips"][c]["marks"],
				"%s: as long as the sprites', the same marks" % c)
	var p := SheetPuppet.new()
	p.height = 128.0
	tree.root.add_child(p)
	p.setup("player")
	check(p.model_mode and p.clip_mode, "drawn as the model")
	var st: Stage3D = p._stage
	check_eq(st.in_use(), 1, "it has a cell of the stage")
	var sk: Skeleton3D = p._cell["skeleton"]
	var anim: AnimationPlayer = p._cell["anim"]
	check_eq(sk.get_bone_count(), 21, "its skeleton")
	check(anim.get_animation_list().size() >= info["clips"].size(), "its animations (%d)" % anim.get_animation_list().size())
	var mesh: MeshInstance3D = (p._cell["model"] as Node3D).find_child("Body", true, false)
	check(mesh.mesh.get_surface_count() == 11 and mesh.get_surface_override_material(0) is ShaderMaterial, "one mesh, its cel shaders")
	check(p._sprite.texture == st.viewport.get_texture() and p._sprite.region_rect == st.region(int(p._cell["slot"])), "the sprite shows its cell of the stage")
	check(absf(float(info["stand_m"]) * p._m - 128.0) < 1.0, "128 px tall on screen")
	# The same controls: standing, walking by the distance walked, the rifle up.
	p._process(DT)
	check_eq(p.shown(), "gun_idle", "standing with the rifle")
	var gun: int = p._cell["gun"]
	p._pose_model(DT)
	check(sk.get_bone_pose_scale(gun).x > 0.9, "the rifle's there")
	p.walk = 1.0
	var poses := {}
	for k in 12:
		p.phase = k / 12.0 * TAU
		p._process(DT)
		p._pose_model(0.0)
		poses[sk.get_bone_pose_rotation(sk.find_bone("thigh.L"))] = true
	check_eq(p.shown(), "gun_walk", "walking")
	check(poses.size() >= 10, "its legs move through the cycle (%d poses)" % poses.size())
	p.walk = 0.0
	p.armed = false
	p.stance = "guard"
	p._process(DT)
	p._pose_model(DT)
	check(p.shown() == "guard" and p._blend > 0.0, "a change of clip is blended")
	for k in 12:
		p._pose_model(DT)
	check(p._blend <= 0.0 and sk.get_bone_pose_scale(gun).x < 0.01, "then it's in its stance, the rifle put away")
	# Turning: any direction, smoothly; the 8 views are still told.
	p.set_facing(Vector2(-1, 0))
	check_eq(p._view, "w", "facing west")
	p._pose_model(DT)
	var y1: float = (p._cell["model"] as Node3D).rotation.y
	for k in 60:
		p._pose_model(DT)
	var y2: float = (p._cell["model"] as Node3D).rotation.y
	check(absf(angle_difference(y1, p._yaw_to)) > 0.5 and absf(angle_difference(y2, p._yaw_to)) < 0.02, "it turns there smoothly")
	# The muzzle: where the sprites have it, from every side.
	SheetPuppet.model3d = false
	var q := SheetPuppet.new()
	q.height = 128.0
	tree.root.add_child(q)
	q.setup("player")
	SheetPuppet.model3d = true
	check(q.clip_mode and not q.model_mode, "(a second one, from the sprites)")
	for i in 8:
		var d := Vector2.from_angle(i * PI / 4.0)
		p.set_facing(d)
		q.set_facing(d)
		check(p.muzzle().distance_to(q.muzzle()) < 3.0, "the muzzle facing %s (%s / %s)" % [SheetPuppet.DIRS[i], p.muzzle(), q.muzzle()])
	q.queue_free()
	# A leap: off the ground, the model itself rising.
	check(p.play("leap"), "a leap")
	var top := 0.0
	var rise := 0.0
	var pelvis := sk.find_bone("pelvis")
	for k in 50:
		p._process(DT)
		p._pose_model(DT)
		top = maxf(top, p.air())
		rise = maxf(rise, sk.get_bone_global_pose(pelvis).origin.y)
	check(top > 40.0 and rise > 1.6, "off the ground (%.0f px; its hips %.2f m up)" % [top, rise])
	check(p.mark_time("jab", "hit") > 0.0 and p.clip_time("jab") > p.mark_time("jab", "hit"), "the clips' marks")
	# The stage has room for a few; then the sprites stand in.
	var more := []
	for k in Stage3D.SLOTS:
		var e := SheetPuppet.new()
		tree.root.add_child(e)
		e.setup("player")
		more.append(e)
	check(more.slice(0, Stage3D.SLOTS - 1).all(func(e): return e.model_mode), "the stage's other cells")
	check(not more[-1].model_mode and more[-1].clip_mode, "the stage full: the next one is drawn from the sprites")
	for e in more:
		e.free()
	check_eq(st.in_use(), 1, "freed, they give their cells back")
	p.free()
	check_eq(st.in_use(), 0, "and so does the first")
	# The setting: rendered sprites instead.
	SheetPuppet.model3d = false
	var r := SheetPuppet.new()
	tree.root.add_child(r)
	r.setup("player")
	check(r.clip_mode and not r.model_mode, "\"rendered sprites\": no model")
	r.free()
	SheetPuppet.model3d = true


## The planet's ground as 3D geometry (Ground3D): a mesh per chunk of the world,
## its heights real, seen by a camera that matches the 2D view to the pixel.
func test_ground_3d() -> void:
	var s: Node = await _surface()
	var g: Ground3D = s.ground3d
	check(g != null and s.ground_chunks == null and s.tile_ground == null, "the ground is 3D geometry - no tile layers, no pictures of them")
	if g == null:
		s.queue_free()
		return
	g.collect(0, true)
	check_eq(g.pending(), 0, "every chunk that's arrived is a mesh")
	check(g.chunk_count() >= 4 and g.chunk_count() == s._gen_count, "one mesh a chunk of the world (%d of %d)" % [g.chunk_count(), s._gen_count])
	var verts := 0
	var stone := 0
	var top := -INF
	var low := INF
	for id in g._chunks:
		var arrays: Array = (g._chunks[id] as MeshInstance3D).mesh.surface_get_arrays(0)
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		verts += vs.size()
		for v in vs:
			top = maxf(top, v.y)
			low = minf(low, v.y)
		var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var nr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		check(uv.size() == vs.size() and nr.size() == vs.size() and vs.size() % 9 == 0
			and (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() == vs.size() / 9 * 24, "chunk %d: a 3 x 3 patch a tile, textured, with normals (lit)" % id)
		if (g._chunks[id] as MeshInstance3D).mesh.get_surface_count() > 1:
			stone += (((g._chunks[id] as MeshInstance3D).mesh.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]) as PackedVector3Array).size()
	check(verts > 4000, "thousands of vertices (%d)" % verts)
	check(stone > 100, "banks and cliffs of stone blocks: geometry of their own (%d vertices)" % stone)
	check(absf(Ground3D.relief(3.0, 4.0)) <= Ground3D.RELIEF and Ground3D.relief(3.0, 4.0) != Ground3D.relief(3.5, 4.0), "the ground rolls: one field over the world")
	check(top - low >= Ground3D.LEVEL_H * 0.99, "the ground has real heights: ledges a level and more apart (%.2f units)" % (top - low))
	# A tile on its level is a square at that height.
	var N: int = s.N
	var c := Vector2i(N / 2, N / 2)
	var k := c.x * N + c.y
	var want_y: float = (int(s._lvl[k]) - s._plot_lvl) * Ground3D.LEVEL_H
	var mi: MeshInstance3D = g._chunks[s._gen_index(c)]
	var found := 0
	for v in (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		if absf(absf(v.x - c.x) - 0.5) < 0.001 and absf(absf(v.z - c.y) - 0.5) < 0.001 and absf(v.y - want_y) <= Ground3D.RELIEF + 0.001:
			found += 1
	check(found >= 4, "the pad's tile: its four corners at its level's height, give or take the roll (%d)" % found)
	# The 3D camera shows it where the 2D world has it, to the pixel.
	g.sync()
	check(g._drawn.has_area() and Vector2(g._vp.size) == s.get_viewport_rect().size + Vector2(Ground3D.MARGIN, Ground3D.MARGIN) * 2.0, "its picture: the window and a margin")
	for cell in [c, c + Vector2i(3, -2), c + Vector2i(-4, 5)]:
		var kk: int = cell.x * N + cell.y
		var y: float = (int(s._lvl[kk]) - s._plot_lvl) * Ground3D.LEVEL_H
		var px: Vector2 = g._cam.unproject_position(Vector3(cell.x, y, cell.y))
		var flat: Vector2 = s._g2w * Vector2(cell)                       # (the tile's centre in the 2D world...)
		flat.y -= (int(s._lvl[kk]) - s._plot_lvl) * s.TTILES.LEVEL_PX      # (... drawn lifted by its level)
		var want: Vector2 = (flat - g._drawn.position) * g._zoom
		check(px.distance_to(want) < 1.0, "tile %s is drawn where the 2D ground had it (%s / %s)" % [cell, px.round(), want.round()])
	# Walking on a little: the picture stays (the view's still inside it); far: drawn again.
	var was: Rect2 = g._drawn
	g._vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	g.sync()
	check(g._drawn == was and g._vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "the same view: nothing drawn again")
	check(s.world_settled(), "the world's settled once its meshes are in")
	s.queue_free()
	await tree.process_frame
	# The 2D ground is still there (the fallback).
	Ground3D.enabled = false
	var s2: Node = await _surface()
	Ground3D.enabled = true
	check(s2.ground3d == null and s2.ground_chunks != null and s2.tile_ground != null, "3D ground off: the tile layers and their pictures")
	s2.queue_free()
	await tree.process_frame


## The inventories' equipment screen shows the actual 3D model; dragging turns it.
func test_model_view() -> void:
	var lp := LoadoutPanel.new()
	tree.root.add_child(lp)
	lp.setup(Gear.DEFAULT_LOADOUT.duplicate(), {}, 12, "carried", Callable())
	await tree.process_frame
	var mv: ModelView = lp._doll.view
	check(mv != null and mv._pivot.get_child_count() == 1, "the equipment screen shows the 3D model")
	check(mv._anim != null and mv._anim.is_playing(), "standing in its idle animation")
	var y0 := ModelView.yaw
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	mv._gui_input(press)
	var drag := InputEventMouseMotion.new()
	drag.relative = Vector2(100, 0)
	mv._gui_input(drag)
	check(absf(angle_difference(y0, ModelView.yaw)) > 1.0 and is_equal_approx(mv._pivot.rotation.y, ModelView.yaw), "a left drag turns it round")
	press.pressed = false
	mv._gui_input(press)
	var y1 := ModelView.yaw
	mv._gui_input(drag)
	check(is_equal_approx(ModelView.yaw, y1), "not once the button's up")
	lp.refresh()
	await tree.process_frame
	check(is_equal_approx((lp._doll.view as ModelView)._pivot.rotation.y, y1), "rebuilt, it keeps its turn")
	SheetPuppet.model3d = false
	lp.refresh()
	check(lp._doll.view == null and lp._doll.picture != null, "not drawn from models: the picture again")
	SheetPuppet.model3d = true
	lp.queue_free()
	await tree.process_frame


## Levels, points, ranks; what's kept in a save.
func test_levels_and_learning() -> void:
	var p := {"toolbar_foot": ["rifle", "medicine", "energy_cell", "", "", "", "", "", ""]}
	var st: Dictionary = Skills.state(p)
	check_eq(int(st["level"]), 1, "level 1 to begin with")
	check_eq(Skills.rank(p, "pygmachia"), 1, "boxing known")
	check(Skills.rank(p, "leap") == 1 and Skills.rank(p, "phlox") == 1 and Skills.rank(p, "keraunos") == 0, "the leap and the fireball too; not the thunderbolt")
	var bar: Array = Inventory.toolbar(p, true)
	check(bar[3] == "skill:pygmachia" and bar[4] == "skill:leap" and bar[5] == "skill:phlox", "the starting skills on the toolbar's free slots (%s)" % [bar])
	check(Inventory.toolbar_id("skill:leap", true) == "skill:leap" and Inventory.toolbar_id("skill:nothing", true) == "", "skills go on the foot toolbar")
	check(Items.exists("skill:phlox") and Items.display_name("skill:phlox") == "Phlox", "a skill is an item with a name")
	# Learning: a point, and the level it needs.
	check_eq(int(st["points"]), Skills.START_POINTS, "points to begin with")
	check(Skills.cant_learn(p, "keraunos") != "", "the thunderbolt needs a higher level")
	check(Skills.learn(p, "pygmachia") and Skills.rank(p, "pygmachia") == 2, "a point raises a rank")
	check_eq(int(st["points"]), Skills.START_POINTS - 1, "and is spent")
	st["points"] = 0
	check(not Skills.learn(p, "leap"), "no points: nothing to learn")
	# Experience.
	check_eq(Skills.add_xp(p, Skills.xp_need(1) - 1), 0, "not quite a level")
	check_eq(Skills.add_xp(p, 1), 1, "a level")
	check(int(st["level"]) == 2 and int(st["points"]) == 1 and int(st["xp"]) == 0, "level 2, a point")
	check(Skills.xp_need(5) > Skills.xp_need(2), "later levels take more")
	st["level"] = 10
	st["points"] = 60
	for id in Skills.SKILLS:
		while Skills.learn(p, id):
			pass
	check(Skills.rank(p, "eidola") == Skills.MAX_RANK and Skills.cant_learn(p, "eidola") != "", "a skill tops out at rank %d" % Skills.MAX_RANK)
	# What ranks do.
	check_eq(Skills.chain("pygmachia", 1), ["jab", "cross"], "rank 1 boxing: two blows")
	check_eq(Skills.chain("pygmachia", 3).size(), 4, "rank 3: the whole chain")
	check(Skills.blow_damage("jab", 5) > Skills.blow_damage("jab", 1), "ranks hit harder")
	check(Skills.cooldown("phlox", 5) < Skills.cooldown("phlox", 1), "and cool down sooner")
	check(int(Skills.spell("eidola", 5)["count"]) == 3 and int(Skills.spell("eidola", 1)["count"]) == 1, "more eidola at rank 5")
	for id in Skills.SKILLS:
		check(Skills.describe(id, 1).split("\n").size() == 2 + Skills.MAX_RANK, "%s: described, a line per rank" % id)
		check(Skills.ORDER.has(id), "%s is in the book" % id)
	# Saved and loaded.
	var pd: Node = load("res://scripts/player_data.gd").new()
	pd.load_save_data(p)
	check(int(pd.skills["level"]) == 10 and int(pd.skills["ranks"]["eidola"]) == 5, "skills are loaded")
	var back: Dictionary = pd.get_save_data()
	check(back["skills"]["ranks"].size() == Skills.SKILLS.size() and back["toolbar_foot"][4] == "skill:leap", "and saved, the toolbar too")
	check(Skills.clean({"level": 99, "ranks": {"phlox": 9, "nothing": 1}})["ranks"] == {"phlox": Skills.MAX_RANK}, "a bad save is made safe")
	pd.free()


## A martial style: the automaton works through its chain of blows on an enemy in reach.
func test_martial_arts() -> void:
	var s: Node = await _surface()
	var p: Node2D = s.pilot
	var foe := _foe(s, p.position + Vector2(60, 0))
	Skills.state(s.state["player"])["ranks"]["pygmachia"] = 3
	p.stamina = 50.0
	check(s.use_skill("pygmachia"), "boxing: used from the toolbar")
	check_eq(p.style, "pygmachia", "you fight in it now")
	check(s._attack_target == foe, "and go for the enemy at hand")
	var moves := []
	var xp0 := int(Skills.state(s.state["player"])["xp"])
	var t := 0.0
	while t < 3.2:
		_run(s, DT)
		t += DT
		if not s._move.is_empty() and (moves.is_empty() or moves[-1] != s._move["move"]):
			moves.append(s._move["move"])
	check(moves.slice(0, 4) == ["jab", "cross", "hook", "uppercut"], "the chain, blow after blow (%s)" % [moves])
	check(foe.hits >= 4, "they land (%d)" % foe.hits)
	check(foe.floored, "the uppercut floors it")
	check(p.stamina < 50.0, "each blow costs stamina (%.1f)" % p.stamina)
	check(int(Skills.state(s.state["player"])["xp"]) > xp0 or Skills.level(s.state["player"]) > 1, "and earns experience")
	check(p.puppet.stance == "guard" and not p.puppet.armed, "the fighting stance, the rifle put away")
	check(p.position.distance_to(foe.position) < 200.0, "(shoved back, it's still near: %.0f px)" % p.position.distance_to(foe.position))
	# Out of reach: no blow thrown (it would walk up first).
	s.stop_attack()
	_run(s, 1.0)
	foe.position = p.position + Vector2(400, 0)
	var n := foe.hits
	s.attack(foe)
	_run(s, 0.5)
	check_eq(foe.hits, n, "out of reach: it closes in first")
	check(p.moving, "walking up to it")
	# Too tired.
	foe.position = p.position + Vector2(60, 0)
	p.stamina = 0.0
	p.moving = false
	_run(s, 1.0)
	check(s._attack_target == null and foe.hits == n, "too tired to fight")
	# The sweep: everyone around.
	_all_ranks(s)
	var ring := [_foe(s, p.position + Vector2(-70, 0)), _foe(s, p.position + Vector2(0, 60)), _foe(s, p.position + Vector2(50, -50))]
	check(s.use_skill("sweep"), "the sweep")
	_run(s, 1.0)
	check(ring.all(func(d): return d.hits == 1 and d.floored), "floors everyone around")
	check(float(s._tool_cd.get("skill:sweep", 0.0)) > 3.0, "and has a cooldown")
	check(not s.use_skill("sweep"), "not again until it's over")
	# The rifle again.
	s.use_item("rifle")
	check_eq(p.style, "rifle", "the rifle tool: back to shooting")
	for d in ring:
		d.queue_free()
	foe.queue_free()
	s.queue_free()
	await tree.process_frame


## The leap: across the ground in the air - nothing hits you up there.
func test_leap_and_comet() -> void:
	var s: Node = await _surface()
	var p: Node2D = s.pilot
	_all_ranks(s, 1)
	var from: Vector2 = p.position
	var dir := Vector2(1, 0.2).normalized()
	check(s.use_skill("leap", from + dir * 2000.0), "a leap")
	var hp0: float = p.hp
	var up := false
	var high := 0.0
	var t := 0.0
	while not s._move.is_empty() and t < 2.0:
		_run(s, DT)
		t += DT
		if p.airborne:
			up = true
			high = maxf(high, p.hop + p.puppet.air())
			p.surface_hit(50.0)
	check(up and high > 40.0, "off the ground (%.0f px up)" % high)
	check(is_equal_approx(p.hp, hp0), "what's fired at you in the air misses")
	var went := p.position.distance_to(from)
	check(went > 200.0 and went <= Skills.reach("leap", 1) + 1.0, "as far as the leap reaches (%.0f px)" % went)
	check(not p.airborne and p.hop == 0.0 and p.busy <= 0.0, "down again")
	check(s.walkable_at(p.position), "on ground you can stand on")
	p.surface_hit(5.0)
	check(p.hp < hp0 or p.shield < p.max_shield, "on the ground you can be hit again")
	# A bolt fired at you as you leap flies on by.
	s._tool_cd.clear()
	p.stamina = Stamina.MAX
	s.use_skill("leap", p.position - dir * 2000.0)
	_run(s, 0.3)
	check(p.airborne, "in the air")
	var bolt = SurfaceProps.LaserBolt.new()
	bolt.accuracy = 1.0
	bolt.position = p.position + Vector2(20, -40)
	bolt.target = p
	bolt.damage = 30.0
	s.objects.add_child(bolt)
	var sh: float = p.shield
	var hp1: float = p.hp
	bolt._process(DT)
	check(bolt.target == null and is_equal_approx(p.shield, sh) and is_equal_approx(p.hp, hp1), "a bolt passes under you")
	_run(s, 1.0)
	# The comet kick: across to an enemy, down it goes.
	s._tool_cd.clear()
	p.stamina = Stamina.MAX
	var foe := _foe(s, p.position + Vector2(260, 0))
	check(s.use_skill("comet"), "a comet kick at an enemy 260 px away")
	_run(s, 1.2)
	check(foe.hits == 1 and foe.floored, "lands on it")
	check(p.position.distance_to(foe.position) < 220.0, "you're there (%.0f px)" % p.position.distance_to(foe.position))
	foe.remove_from_group("surface_hostiles")
	foe.queue_free()
	s._tool_cd.clear()
	s.stop_attack()
	_run(s, 0.5)
	check(not s.use_skill("comet"), "no enemy in reach: no kick")
	s.queue_free()
	await tree.process_frame


## The arcana: the beam, the fireball, the thunderbolt, the dome, the eidola; the guard.
func test_spells() -> void:
	var s: Node = await _surface()
	var p: Node2D = s.pilot
	_all_ranks(s, 1)
	var at: Vector2 = p.position
	# Phlox: flies, bursts, burns.
	var a := _foe(s, at + Vector2(300, 0))
	var b := _foe(s, at + Vector2(340, 30))
	var far := _foe(s, at + Vector2(-500, 0))
	check(s.use_skill("phlox", a.position), "a fireball")
	check(p.busy > 0.0 and not p.moving, "you stand to cast it")
	_run(s, 1.6)
	check(a.hits >= 1 and b.hits >= 1 and far.hits == 0, "bursts on those near where it lands (%d, %d, %d)" % [a.hits, b.hits, far.hits])
	var n := a.hits
	_run(s, 2.0)
	check(a.hits > n, "and leaves them burning")
	check(float(s._tool_cd.get("skill:phlox", 0.0)) > 0.0 and p.stamina < Stamina.MAX, "cooldown and stamina")
	# The lance: through everything in its line.
	for d in [a, b, far]:
		d.hits = 0
	a.position = at + Vector2(200, 0)
	b.position = at + Vector2(420, 6)
	far.position = at + Vector2(100, 300)
	s._burns.clear()
	check(s.use_skill("lance", at + Vector2(600, 0)), "the lance")
	_run(s, 1.4)
	check(a.hits >= 2 and b.hits >= 2 and far.hits == 0, "through both in its line, not the one aside (%d, %d, %d)" % [a.hits, b.hits, far.hits])
	# Keraunos: one struck, the next leapt to.
	for d in [a, b, far]:
		d.hits = 0
		d.taken = 0.0
	b.position = a.position + Vector2(120, 0)
	far.position = a.position + Vector2(-900, 0)
	check(s.use_skill("keraunos", a.position), "the thunderbolt")
	_run(s, 1.2)
	check(a.hits == 1 and b.hits == 1 and far.hits == 0, "strikes one and leaps to the next near (%d, %d, %d)" % [a.hits, b.hits, far.hits])
	check(b.taken < a.taken and a.staggered > 0.0, "at half strength; it stuns")
	# The dome: soaks what's thrown at you, throws back those too close.
	a.position = p.position + Vector2(60, 0)
	a.hits = 0
	check(s.use_skill("aegis"), "the dome")
	_run(s, 1.0)
	check(p.dome != null and p.dome_left > 0.0, "is up")
	check(a.hits == 1 and a.position.distance_to(p.position) > 100.0, "throws back the one standing close (%.0f px)" % a.position.distance_to(p.position))
	var hp0: float = p.hp
	var sh0: float = p.shield
	p.surface_hit(40.0)
	check(is_equal_approx(p.hp, hp0) and is_equal_approx(p.shield, sh0), "soaks a hit")
	p.surface_hit(100.0)
	check(p.dome_left <= 0.0 and (p.hp < hp0 or p.shield < sh0), "until it breaks")
	# The guard.
	p.hp = p.max_hp
	p.shield = 0.0
	check(s.use_skill("guard"), "the guard")
	p.surface_hit(20.0)
	var lost: float = p.max_hp - p.hp
	check(lost > 0.0 and lost < 12.0, "most of a hit shrugged off (%.1f of 20)" % lost)
	_run(s, 2.5)
	check(p.guard_left <= 0.0 and p.busy <= 0.0, "for a moment")
	# The eidola.
	_all_ranks(s, 5)
	s._tool_cd.clear()
	a.position = p.position + Vector2(160, 0)
	a.hits = 0
	var npcs: int = s.npcs.size()
	check(s.use_skill("eidola"), "the eidola")
	_run(s, 1.0)
	var eid: Array = s.npcs.filter(func(e): return e.species == "eidolon")
	check_eq(eid.size(), 3, "three of them at rank 5")
	_run(s, 4.0, eid)
	check(a.hits > 0, "they go for your enemy (%d blows)" % a.hits)
	for e in eid:
		e.life = 0.01
	_run(s, 0.1, eid)
	check_eq(s.npcs.size(), npcs, "and fade when their time's up")
	# Not learned: nothing.
	Skills.state(s.state["player"])["ranks"]["phlox"] = 0
	s._tool_cd.clear()
	check(not s.use_skill("phlox", a.position), "a skill not learned can't be used")
	for d in [a, b, far]:
		d.queue_free()
	s.queue_free()
	await tree.process_frame


## Pirates fight hand to hand up close; a blow of yours staggers them, a finisher floors them.
func test_pirates_brawl() -> void:
	var s: Node = await _surface()
	var p: Node2D = s.pilot
	var at: Vector2 = p.position
	var pz: Node2D = s._spawn_npc(at + Vector2(64, 0), 1, at + Vector2(64, 0), "pirate")
	await tree.process_frame
	pz.set_process(false)
	check(pz.puppet.clip_mode, "the pirate is drawn from its clips")
	p.max_hp = 500.0
	p.hp = 500.0
	p.shield = 0.0
	var t := 0.0
	var states := {}
	var blows := {}
	while t < 6.0:
		pz._process(DT)
		pz.puppet._process(DT)
		t += DT
		states[pz._state] = true
		if pz.puppet.playing() != "":
			blows[pz.puppet.playing()] = true
	check(states.has("brawl"), "this close it fights hand to hand (%s)" % [states.keys()])
	check(not pz.puppet.armed, "the rifle slung")
	check(blows.size() >= 2, "throwing different blows (%s)" % [blows.keys()])
	check(p.hp < 500.0, "that land on you (%.0f)" % p.hp)
	check(get_tree_bolts(s) == 0, "no shots fired")
	# Staggered, it does nothing; floored, it gets up again.
	var hp0: float = p.hp
	pz._blow = {}
	pz.stagger(1.2, true)
	check(pz.puppet.playing() == "ko", "floored")
	t = 0.0
	while t < 0.7:
		pz._process(DT)
		pz.puppet._process(DT)
		t += DT
	check(is_equal_approx(p.hp, hp0), "it can't hit you while it's down")
	while t < 2.0:
		pz._process(DT)
		pz.puppet._process(DT)
		t += DT
	check(pz._stun <= 0.0 and pz.puppet.playing() != "ko", "then it's up again")
	# Step away: it takes up the rifle again (or comes after you, if it's a brawler).
	check(not pz.brawler and pz.variant % 3 != 0, "(this one's no brawler)")
	p.position = at + Vector2(-330, 0)
	t = 0.0
	while t < 2.0 and pz._state == "brawl":
		pz._process(DT)
		pz.puppet._process(DT)
		t += DT
	check(pz._state != "brawl", "out of arm's reach: the rifle again (%s)" % pz._state)
	var br: Node2D = s._spawn_npc(at + Vector2(300, 0), 3, at + Vector2(300, 0), "pirate")
	await tree.process_frame
	br.set_process(false)
	check(br.brawler, "every third pirate is a brawler")
	p.position = at
	t = 0.0
	while t < 1.0:
		br._process(DT)
		t += DT
	check(br._state == "brawl" and br.position.distance_to(p.position) < 290.0, "it charges instead of shooting (%s, %.0f px)" % [br._state, br.position.distance_to(p.position)])
	# Beaten: it falls (its own fall), loot drops.
	br.set_process(true)
	br.last_hit_by = p
	var lv := Skills.level(s.state["player"])
	var xp := int(Skills.state(s.state["player"])["xp"])
	br.surface_hit(1000.0)
	check(br.dead and br.puppet.playing() == "ko", "down it goes")
	check(int(Skills.state(s.state["player"])["xp"]) > xp or Skills.level(s.state["player"]) > lv, "a kill of yours earns experience")
	pz.queue_free()
	s.queue_free()
	await tree.process_frame


## On the classic hand-drawn sheets (the backup) the skills still work - without their animations.
func test_skills_on_classic_sprites() -> void:
	SheetPuppet.classic = true
	var s: Node = await _surface()
	SheetPuppet.classic = false
	var p: Node2D = s.pilot
	check(not p.puppet.clip_mode, "the automaton is drawn from its classic sheets")
	_all_ranks(s)
	var foe := _foe(s, p.position + Vector2(60, 0))
	check(s.use_skill("pankration"), "a martial style")
	_run(s, 1.5)
	check(foe.hits >= 2, "its blows land (%d)" % foe.hits)
	s.stop_attack()
	_run(s, 0.6)
	var from: Vector2 = p.position
	check(s.use_skill("leap", from + Vector2(-1500, 0)), "the leap")
	_run(s, 1.0)
	check(p.position.distance_to(from) > 200.0 and not p.airborne, "carries you across (%.0f px)" % p.position.distance_to(from))
	foe.hits = 0
	check(s.use_skill("keraunos", foe.position), "a spell")
	_run(s, 1.0)
	check(foe.hits >= 1, "strikes")
	foe.queue_free()
	s.queue_free()
	await tree.process_frame


func get_tree_bolts(s: Node) -> int:
	return s.objects.get_children().filter(func(c): return c is SurfaceProps.LaserBolt).size()


## The Spell Book and the toolbar.
func test_spell_book() -> void:
	var s: Node = await _surface()
	s.field_menu.open(s.field_menu.SKILLS_TAB)
	await tree.process_frame
	var page = s.field_menu._pages[s.field_menu.SKILLS_TAB]
	check(s.field_menu.visible and page.visible, "K's tab of the Field Computer")
	check(page._head.text.contains("LEVEL 1") and page._head.text.contains("2 skill points"), "your level and points (%s)" % page._head.text)
	var st: Dictionary = Skills.state(s.state["player"])
	page._learn("leap")
	check(Skills.rank(s.state["player"], "leap") == 2 and int(st["points"]) == 1, "a point spent on the leap")
	st["level"] = 3
	page._learn("lance")
	check(s.foot_toolbar().has("skill:lance"), "a new skill goes on a free toolbar slot (%s)" % [s.foot_toolbar()])
	page._hovered = "skill:lance"
	var key := InputEventKey.new()
	key.keycode = KEY_9
	key.pressed = true
	page._input(key)
	check_eq(s.foot_toolbar()[8], "skill:lance", "9 over it: on that slot")
	page._describe("phlox")
	check(page._text.text.contains("Rank 5") and page._name.text.contains("PHLOX"), "a skill in full on the right")
	s.field_menu.close()
	# The toolbar: a slot's key uses the skill.
	var foe := _foe(s, s.pilot.position + Vector2(60, 0))
	var k4 := InputEventKey.new()
	k4.keycode = KEY_4
	k4.pressed = true
	s.field_menu.hide()
	s._input(k4)
	check_eq(s.pilot.style, "pygmachia", "4: boxing")
	check(s.toolbar._get_tooltip(s.toolbar.slot_rect(3).get_center()).contains("Pygmachia"), "its tooltip")
	foe.queue_free()
	s.queue_free()
	await tree.process_frame
