extends TestCase
## Planet surfaces: everything reachable, walking through doors, no stuck walks.

const PLANETS := ["thalassa", "selene", "krystallos"]
const DT := 1.0 / 60.0

var _old_planet := ""


func _surface(pid: String) -> Node:
	SaveGame.landed_planet = pid
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	s.set_process(false)
	for d in s.all_doors():
		d.set_process(false)
	return s


func setup() -> void:
	_old_planet = SaveGame.landed_planet


func teardown() -> void:
	SaveGame.landed_planet = _old_planet
	Accuracy.sure = false
	Ground3D.enabled = true
	SheetPuppet.classic = false


## Walks the pilot to `to` like the game does; true if it gets there.
func _walk(s: Node, from: Vector2, to: Vector2, limit := 20.0) -> bool:
	s.pilot.position = from
	_settle_nav(s)
	s._walk_to(to)
	var t := 0.0
	var doors: Array = s.all_doors()
	while t < limit and s.pilot.moving:
		s._process(DT)
		for d in doors:
			d._process(DT)
		t += DT
	return s.pilot.position.distance_to(to) < 14.0


## The path grid caught up with where the pilot was put (a jump far away
## re-centres it on a worker thread; until it's swapped in, paths from there
## are cut short - in the game you walk, and it follows you).
func _settle_nav(s: Node) -> void:
	s._stream_nav()
	var t0 := Time.get_ticks_msec()
	while s._nav_task >= 0 and Time.get_ticks_msec() - t0 < 5000:
		OS.delay_msec(2)
		s._poll_nav()


func _inside(s: Node, b, rng: RandomNumberGenerator) -> Vector2:
	for k in 60:
		var c := Vector2i(rng.randi_range(b.rect.position.x, b.rect.end.x - 1), rng.randi_range(b.rect.position.y, b.rect.end.y - 1))
		var p: Vector2 = s._cell_pos(c) + Vector2(rng.randf_range(-20, 20), rng.randf_range(-10, 10))
		if s.walkable_at(p, 10.0):
			return p
	return Vector2.INF


func test_everything_reachable() -> void:
	for pid in PLANETS:
		var s: Node = await _surface(pid)
		var reached: Dictionary = s._flood(s._nearest_free(s._nav_point(s.lander.position + Vector2(0, 90))))
		# (ground reached only by going round a cliff outside the path grid's
		# window is reached as the window follows you: only what the tiles
		# reach inside the window must be reachable in it)
		var win: Rect2i = s._nav_window()
		var N: int = s.N
		var walk := PackedByteArray()
		walk.resize(N * N)
		s._walk_open(walk)
		var tiles := {}
		var start: Vector2i = s._cell_at(s.lander.position + Vector2(0, 90))
		var queue: Array[Vector2i] = [start]
		tiles[start] = true
		var head := 0
		while head < queue.size():
			var c: Vector2i = queue[head]
			head += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = c + d
				if win.has_point(q) and not tiles.has(q) and walk[q.x * N + q.y] == 1 \
						and (not s._tiled or s._step_ok_t(c.x * N + c.y, q.x * N + q.y)):
					tiles[q] = true
					queue.append(q)
		var missing := 0
		for tp in s._reach_targets():
			var c: Vector2i = s._cell_at(tp)
			var by_tiles: bool = tiles.has(c) or tiles.has(c + Vector2i(1, 0)) or tiles.has(c - Vector2i(1, 0)) or tiles.has(c + Vector2i(0, 1)) or tiles.has(c - Vector2i(0, 1))
			if s._tiled:
				by_tiles = tiles.has(c)   # (a neighbour may be a level below)
			if by_tiles and not reached.has(s._nearest_free(s._nav_point(tp))):
				missing += 1
		check_eq(missing, 0, pid + ": unreachable targets")
		s.queue_free()
		await tree.process_frame


func test_walk_into_and_out_of_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for pid in PLANETS:
		var s: Node = await _surface(pid)
		var tried := 0
		# The buildings in the path grid's window as you land (walking about
		# streams in more, beyond the window - this test drives frames itself).
		for b in s.buildings.filter(func(b): return s.in_nav(b.bounds.get_center(), 12)):
			for k in 6:
				var a: Vector2
				var z: Vector2
				match k % 3:
					0:
						a = b.bounds.get_center() + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(250, 500)
						z = _inside(s, b, rng)
					1:
						a = _inside(s, b, rng)
						z = b.bounds.get_center() + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(250, 500)
					_:
						a = _inside(s, b, rng)
						z = _inside(s, b, rng)
				if a == Vector2.INF or z == Vector2.INF or not s.walkable_at(a, 10.0) or not s.walkable_at(z, 10.0):
					continue
				if s._flood(s._nearest_free(s._nav_point(a))).has(s._nearest_free(s._nav_point(z))):
					tried += 1
					check(_walk(s, a, z), "%s %s: walk %s -> %s fails" % [pid, b.title, a.round(), z.round()])
		check(tried >= 10, "%s: only %d building routes tested" % [pid, tried])
		s.queue_free()
		await tree.process_frame


## Furniture inside the buildings: against the back walls, out of the
## doorways and off the stairs, blocking walking; chests, lockers and vaults
## open once (loot), and stay open when the building is rebuilt.
func test_furniture() -> void:
	SaveGame.space_state = {}
	var s: Node = await _surface("thalassa")
	check(not s.buildings.is_empty(), "buildings")
	var f: Furniture = null
	for b in s.buildings:
		check(b.furniture.size() >= 3, "%s: furnished (%d pieces)" % [b.style, b.furniture.size()])
		check(b.furniture.any(func(x): return x.is_container()), "%s: at least one container" % b.style)
		var count := {}
		for x in b.furniture:
			count[x.kind] = count.get(x.kind, 0) + 1
			check(x.kind in s.FURNITURE[b.style], "%s: a %s belongs here" % [b.style, x.kind])
			if not x.is_flat():
				check(not s.walkable_at(x.position), "%s: you can't walk through the %s" % [b.style, x.kind])
			check(not s._near_door(x.position, 40.0), "%s: the %s isn't in a doorway" % [b.style, x.kind])
			if b.upper != null:
				for c in [b.upper.stair_a, b.upper.stair_0, b.upper.stair_1]:
					check(x.cell != c, "%s: nothing on the stairs" % b.style)
			if x.is_container():
				check(s.walkable_at(x.approach()), "%s: you can reach the %s" % [b.style, x.kind])
				if f == null:
					f = x
		for k in count:
			check(count[k] <= s.MAX_EACH_KIND, "%s: at most %d %s" % [b.style, s.MAX_EACH_KIND, k])
	if f == null:
		return
	check(s._thing_at(f.click_center() - Vector2(0, s.lift_at(f.global_position))) == f, "a container can be clicked (where it's drawn)")
	var cr := int(s.state["player"]["credits"])
	var items: Dictionary = s.state["player"]["items"].duplicate()
	s.open_container(f)
	check(f.opened and f.title.contains("empty"), "opened: empty now")
	check(int(s.state["player"]["credits"]) > cr or s.state["player"]["items"] != items, "you took what was inside")
	check(s.state["planets"]["thalassa"]["opened"].has(f.key), "remembered")
	var cr2 := int(s.state["player"]["credits"])
	s.open_container(f)
	check_eq(int(s.state["player"]["credits"]), cr2, "nothing more the second time")
	# Rebuilt (as when you come back): the same furniture, the container still open.
	var b0 = s.buildings.filter(func(b): return b.furniture.has(f))[0]
	var spec: Dictionary = b0.spec.duplicate(true)
	var kinds: Array = b0.furniture.map(func(x): return [x.kind, x.key])
	s._remove_building(b0)
	var b1 = s._build_from_spec(spec)
	check_eq(b1.furniture.map(func(x): return [x.kind, x.key]), kinds, "rebuilt: the same furniture")
	check(b1.furniture.filter(func(x): return x.key == f.key)[0].opened, "the opened container stays open")
	# Every kind is painted (but the vault), facing into the room from either wall.
	for k in Furniture.KINDS:
		for w in ["nw", "ne"]:
			var pic := Furniture.picture(k, w)
			check((pic[0] != null) == (k != "vault" and not Furniture.CODE_SIZE.has(k)), "the %s's picture against the %s wall (none: drawn in code)" % [k, w])
			if pic[0] != null:
				check(pic[1].y > 0.0 and pic[1].y <= pic[0].get_height(), "%s: it stands inside its picture" % k)
	check(Furniture.picture("bed", "ne")[0] != Furniture.picture("bed", "nw")[0], "a bed has a picture for each wall")
	var sfx: Node = tree.root.get_node("Sfx")
	for k in ["chest_open", "locker_open", "vault_open"]:
		check_eq(sfx.takes("surface/" + k).size(), 2, "the %s sound" % k)
	s.queue_free()
	await tree.process_frame


## Doors open only close up (REACH), and you hear them open and close.
func test_door_reach_and_sounds() -> void:
	var s: Node = await _surface("thalassa")
	var sfx: Node = tree.root.get_node("Sfx")
	check_eq(sfx.takes("surface/door_open").size(), 3, "three door-opening takes")
	check_eq(sfx.takes("surface/door_close").size(), 3, "three door-closing takes")
	var d: Node2D = null
	for dd in s.all_doors():
		var m: Vector2 = dd.start + dd.dir * 0.5
		if s.walkable_at(m + Vector2(-dd.dir.y, dd.dir.x).normalized() * 140.0):
			d = dd
			break
	check(d != null, "a door with room in front of it")
	if d == null:
		return
	var mid: Vector2 = d.start + d.dir * 0.5
	var nrm: Vector2 = Vector2(-d.dir.y, d.dir.x).normalized()
	s.pilot.moving = false
	s.pilot.path = PackedVector2Array()
	s.pilot.position = mid + nrm * 140.0
	for i in 30:
		d._process(DT)
	check_eq(d.open, 0.0, "standing 140 px away: it stays shut")
	d.last_sound = null
	s.pilot.position = mid + nrm * 60.0
	d._process(DT)
	check(d.last_sound != null and d.last_sound.stream in sfx.takes("surface/door_open"), "coming close: you hear it open (%s)" % d.last_sound)
	for i in 30:
		d._process(DT)
	check(d.open > 0.9, "and it opens")
	s.pilot.position = mid + nrm * 200.0
	d._process(DT)
	check(d.last_sound != null and d.last_sound.stream in sfx.takes("surface/door_close"), "walking off: you hear it close")
	s.queue_free()
	await tree.process_frame


func test_doors_open_before_you_pass() -> void:
	for pid in PLANETS:
		var s: Node = await _surface(pid)
		for d in s.all_doors():
			var mid: Vector2 = d.start + d.dir * 0.5
			var nrm: Vector2 = Vector2(-d.dir.y, d.dir.x).normalized()
			var from: Vector2 = mid + nrm * 110.0
			var to: Vector2 = mid - nrm * 90.0
			if not s.walkable_at(from) or not s.walkable_at(to):
				continue
			for dd in s.all_doors():
				dd.open = 0.0
			s.pilot.position = from
			s._walk_to(to)
			var t := 0.0
			var side := signf((s.pilot.position - mid).dot(nrm))
			while t < 10.0 and s.pilot.moving:
				s._process(DT)
				d._process(DT)
				t += DT
				var now := signf((s.pilot.position - mid).dot(nrm))
				if now != side and s.pilot.position.distance_to(mid) < 40.0:
					check(d.open >= 0.6, "%s: walked through a closed door at %s" % [pid, mid.round()])
					side = now
			check(s.pilot.position.distance_to(to) < 14.0, "%s: did not get through the door at %s" % [pid, mid.round()])
		s.queue_free()
		await tree.process_frame


func test_no_walk_gets_stuck() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var s: Node = await _surface("thalassa")
	var c: Vector2 = s.lander.position
	var n := 0
	while n < 60:
		var a := c + Vector2(rng.randf_range(-1500, 1500), rng.randf_range(-800, 800))
		var z := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(100, 900)
		if not s.walkable_at(a, 10.0) or not s.walkable_at(z, 10.0):
			continue
		n += 1
		s.pilot.position = a
		s._walk_to(z)
		var t := 0.0
		var doors: Array = s.all_doors()
		while t < 25.0 and s.pilot.moving:
			s._process(DT)
			for d in doors:
				d._process(DT)
			t += DT
		check(not s.pilot.moving, "walk %s -> %s still going after 25 s" % [a.round(), z.round()])
	s.queue_free()
	await tree.process_frame


func test_minoan_buildings_and_no_ruins() -> void:
	for pid in PLANETS:
		var s: Node = await _surface(pid)
		check(not ("ruins" in s), pid + ": ruins are gone")
		var styles := {}
		for b in s.buildings:
			check_eq(b.material, "minoan", "%s: %s is built from the Minoan tile sets" % [pid, b.title])
			styles[b.style] = true
			for w in b.walls:
				check(w.texture != null and w.texture.get_width() == 64 * MinoanTiles.RES, "%s: tile-set wall texture" % pid)
		check(styles.has("palace"), pid + ": a palace")
		check(styles.has("warehouse") or styles.has("temple"), pid + ": warehouse / temple buildings")
		s.queue_free()
		await tree.process_frame


func test_minoan_citizens() -> void:
	var s: Node = await _surface("thalassa")
	check(not ("aliens" in s), "aliens are gone")
	check(s.npcs.size() >= 6, "Minoan citizens on the surface")
	var kinds := {}
	for a in s.npcs:
		if a.species == "pirate":
			continue   # (see test_pirates)
		kinds[a.species] = true
		check(a.puppet is SheetPuppet and a.puppet._sprite.texture != null, "the guard is drawn from its sprite sheets")
	for k in SurfaceProps.CITIZENS:
		check(kinds.has(k), "Minoan citizens on the surface: " + k)
	check_eq(kinds.size(), SurfaceProps.CITIZENS.size(), "only guards")
	# Every walking direction has a view of its own (mirrored for the left).
	for a in s.npcs.slice(0, 2):
		var seen := {}
		for d in [Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(1, -1)]:
			a.puppet.set_facing(d)
			seen[a.puppet._view] = true
		check_eq(seen.size(), 4, "%s: side, front 3/4, front and back 3/4 views" % a.species)
	for b in s.buildings:
		check(str(b.title).begins_with("Minoan"), "no alien houses: " + str(b.title))
	s.queue_free()
	await tree.process_frame


## You on foot: 8 relaxed views facing the way you walk; the aiming pose only
## while firing at an enemy (right-click / F), then back to relaxed.
## (On the classic hand-drawn sheets - the backup, Settings.character_graphics;
## the rendered animations: test_skills.)
func test_pilot_sprites_and_firing() -> void:
	Accuracy.sure = true   # (the bolts measured, not the aim)
	SheetPuppet.classic = true
	var s: Node = await _surface("thalassa")
	SheetPuppet.classic = false
	var p: Node2D = s.pilot
	var seen := {}
	for i in 8:
		p.face(Vector2.from_angle(i * PI / 4.0))
		seen[p.sprite.texture] = true
		check(p.sprite.texture.resource_path.contains("player_idle_"), "relaxed when not firing")
	check_eq(seen.size(), 8, "a view of its own for each of the 8 directions")
	var h: float = p.sprite.texture.get_height() * p.sprite.scale.y
	check(h > 120.0 and h < 135.0, "full size: about 128 px tall (%.0f)" % h)
	var start: Vector2 = p.position
	p.position = start + Vector2(-30, 0)   # walking west
	p._process(0.016)
	check_eq(p.view, "w", "faces the way it walks")
	# An enemy to the east: hold the trigger on it.
	var foe := Dummy.new()
	foe.add_to_group("surface_hostiles")
	foe.position = p.position + Vector2(300, 0)
	s.objects.add_child(foe)
	check(s.nearest_hostile() == foe, "F picks the nearest enemy in reach")
	p.trigger = foe
	for i in 60:
		await tree.process_frame
	check(p.aiming() and p.sprite.texture.resource_path.contains("player_aim_"), "the aiming pose while firing")
	check_eq(p.view, "e", "turned to the enemy")
	check(foe.hits > 0, "the bolts hit it (%d)" % foe.hits)
	p.trigger = null
	var t0 := Time.get_ticks_msec()
	while p.aiming() and Time.get_ticks_msec() - t0 < 3000:   # (the rifle stays up a moment)
		await tree.process_frame
	await tree.process_frame
	check(not p.aiming() and p.sprite.texture.resource_path.contains("player_idle_"), "relaxed again after firing")
	foe.position = p.position + Vector2(5000, 0)
	check(not p.fire_at(foe), "no shot out of reach")
	foe.queue_free()
	p.position = start
	s.queue_free()
	await tree.process_frame


func test_guard_sprite_sheets() -> void:
	var g: Node2D = SurfaceProps.citizen("gunner")
	tree.root.add_child(g)
	await tree.process_frame
	var p: SheetPuppet = g.puppet
	var idle := {}
	var aim := {}
	for i in 8:
		p.set_facing(Vector2.from_angle(i * PI / 4.0))
		p.raise_amt = 0.0
		p._process(0.016)
		idle[p._sprite.texture] = true
		p.raise_amt = 1.0
		p._process(0.016)
		aim[p._sprite.texture] = true
		check(p._sprite.texture.resource_path.contains("guard_aim_"), "aiming view while the rifle is up (%s)" % p._view)
	check_eq(idle.size(), 8, "8 relaxed views")
	check_eq(aim.size(), 8, "8 aiming views")
	p.set_facing(Vector2.RIGHT)
	p._process(0.016)
	check(p.muzzle().x > 20.0 and p.muzzle().y < -60.0, "facing east, the muzzle is ahead at chest height (%s)" % p.muzzle())
	var h: float = p._sprite.texture.get_height() * p._sprite.scale.y
	check(absf(h - SheetPuppet.HEIGHT) < 2.0, "drawn %.0f px tall" % h)
	g.queue_free()
	await tree.process_frame


## Pirates: bands all over the planet (and near you), shooting you and the
## citizens but never each other, shot back by guards and by you, dropping
## loot when they fall; and you get knocked out (back to your ship) at 0 health.
## The pirate is drawn from its four reference sheets (tools/character_sheets.py):
## idle, raise1, raise2, aim in 8 views, no walk frames - walking bobs and sways;
## each picture stands on the middle of its feet; raising overrides walking.
func test_pirate_frames() -> void:
	SheetPuppet.classic = true         # (the classic sheets: the backup)
	var p := SheetPuppet.new()
	tree.root.add_child(p)
	p.setup("pirate")
	SheetPuppet.classic = false
	check_eq(p.walk_frames, 0, "no walk frames: walking bobs and sways")
	check_eq(p.sequence, ["idle", "raise1", "raise2", "aim"], "the four poses of the sheets, in order")
	var hs := []
	for pose in p.sequence:
		for d in SheetPuppet.DIRS:
			var path := "res://art/pirate/pirate_%s_%s.png" % [pose, d]
			if check(ResourceLoader.exists(path), path + " exists"):
				var f: Dictionary = p._frame(pose, d)
				hs.append(f["tex"].get_height())
				check(f["anchor"].x > f["tex"].get_width() * 0.2 and f["anchor"].x < f["tex"].get_width() * 0.8, "%s %s stands under its body" % [pose, d])
	check(hs.min() > 240 and hs.max() < 275, "every picture about the same height - no jump between poses (%d-%d)" % [hs.min(), hs.max()])
	# The side views aim from the rifle's far end.
	var e: Dictionary = p._frame("aim", "e")
	var w: Dictionary = p._frame("aim", "w")
	check(e["muzzle"].x > e["tex"].get_width() * 0.75, "aiming east: the muzzle at the right end (%s)" % e["muzzle"])
	check(w["muzzle"].x < w["tex"].get_width() * 0.25, "aiming west (east mirrored): at the left end (%s)" % w["muzzle"])
	p.walk = 1.0
	var ys := []
	for k in 24:
		p.phase = k / 24.0 * TAU
		p._process(0.016)
		ys.append(p._sprite.position.y)
		check_eq(p._pose, "idle", "walking shows the relaxed pose")
	check(ys.max() - ys.min() > 0.5, "with a bob (%s)" % [ys])
	p.raise_amt = 1.0
	p._process(0.016)
	check_eq(p._pose, "aim", "aiming overrides walking")
	p.queue_free()


func test_pirates() -> void:
	SheetPuppet.classic = true         # (the classic sheets: the backup)
	var s: Node = await _surface("thalassa")
	var planned: Array = s._npc_plans.filter(func(n): return n["kind"] == "pirate")
	check(planned.size() >= 50, "plenty of pirates on the planet (%d)" % planned.size())
	var near: Array = s.npcs.filter(func(n): return n.species == "pirate")
	check(not near.is_empty(), "pirates around the landing site (%d)" % near.size())
	var nearest := INF
	for n in planned:
		nearest = minf(nearest, n["pos"].distance_to(s.lander.position))
	check(nearest > 600.0, "not right on the landing pad (%.0f px)" % nearest)
	for p in near:
		check(p.puppet is SheetPuppet and p.puppet._sprite.texture.resource_path.contains("pirate_"), "a pirate is drawn from its sprite sheet")
	# Four frames: rifle down while not attacking, raised through the frames to fire.
	var pz: Node2D = near[0]
	var frames := ["idle", "raise1", "raise2", "aim"]
	check_eq(pz.puppet.sequence, frames, "the pirate's 4 attack frames")
	pz.set_process(false)
	pz._walk = 0.0                     # (standing: walking would show the walk cycle)
	pz.puppet.walk = 0.0
	pz.puppet._process(0.016)
	check(pz.puppet._sprite.texture.resource_path.contains("pirate_idle_"), "rifle down (frame 1) when not attacking")
	var seen := []
	pz._aim_at = s.pilot
	pz._go("raise")
	for i in 60:
		pz._process(0.02)
		pz.puppet._process(0.02)
		var fr: String = pz.puppet._pose
		if seen.is_empty() or seen[-1] != fr:
			seen.append(fr)
	check(seen.slice(0, 4) == frames, "raising the rifle runs through every frame, firing from the last (%s)" % [seen])
	pz.set_process(true)
	# A pirate next to you and a guard: it picks the nearest - never a pirate.
	var at: Vector2 = s.pilot.position
	var pa: Node2D = s._spawn_npc(at + Vector2(200, 0), 1, at + Vector2(200, 0), "pirate")
	var pb: Node2D = s._spawn_npc(at + Vector2(240, 30), 2, at + Vector2(240, 30), "pirate")
	await tree.process_frame
	check(pa._target() == s.pilot, "it aims at you")
	check(pa.is_in_group("surface_hostiles"), "guards and you count it as hostile")
	s.pilot.position = at + Vector2(-3000, 0)   # (you're away: only other pirates are close)
	check(pa._target() != pb, "never at another pirate")
	s.pilot.position = at
	var hp0: float = s.pilot.hp + s.pilot.shield   # (health and shield: a hit takes the shield first)
	for i in 240:
		await tree.process_frame
		if s.pilot.hp + s.pilot.shield < hp0:
			break
	check(s.pilot.hp + s.pilot.shield < hp0, "its bolts hurt you (%.0f -> %.0f)" % [hp0, s.pilot.hp + s.pilot.shield])
	# Down it goes: loot where it fell, yours when you walk over it.
	var credits := int(s.state["player"]["credits"])
	pa.surface_hit(1000.0)
	check(pa.dead and not s.npcs.has(pa) and not pa.is_in_group("surface_hostiles"), "a shot-down pirate is out of the fight")
	check(s.loot.size() == 1, "it dropped loot")
	s.pilot.position = s.loot[0].position
	s._collect_loot()
	check(s.loot.is_empty() and int(s.state["player"]["credits"]) > credits, "walking over the loot takes it (%d -> %d credits)" % [credits, int(s.state["player"]["credits"])])
	# Knocked out: back at your ship, healed, a tenth of your credits gone.
	credits = int(s.state["player"]["credits"])
	s.pilot.position = at + Vector2(400, 300)
	s.pilot.surface_hit(1000.0)
	check(is_equal_approx(s.pilot.hp, s.pilot.max_hp) and s.pilot.position.distance_to(s.lander.position) < 150.0, "knocked out: you come to beside your ship")
	check(int(s.state["player"]["credits"]) == credits - int(credits * 0.1), "and the pirates took a tenth of your credits")
	# Citizens can fall too.
	var g: Node2D = s.npcs.filter(func(n): return n.species == "gunner")[0]
	g.surface_hit(10000.0)
	check(g.dead and not s.npcs.has(g), "a citizen can fall")
	pb.queue_free()
	s.queue_free()
	await tree.process_frame


## You shoot enemies: click one (anywhere on it, left or right button) and
## you close in if it's out of range and fire until it falls; a click on the
## ground ends the fight; F attacks the nearest; the cursor is a crosshair over them.
## Shot at, a pirate fights back - closing in when you shoot from beyond its
## reach; badly hurt, it lowers its rifle and runs, and won't pick a fight.
func test_pirates_fight_back_and_flee() -> void:
	var s: Node = await _surface("thalassa")
	s.stop_attack()            # (you don't fire at it on your own here)
	for n in s.npcs:
		n.set_process(false)   # (only you and ours in this test: the guards
		n.position += Vector2(0, 20000)   # would join in)
	var at: Vector2 = s.pilot.position
	# Somewhere open, out of the pirate's reach but in yours (560 < 650 < 700).
	var spot := Vector2.INF
	for k in 24:
		var p: Vector2 = at + Vector2.from_angle(k * TAU / 24.0) * 650.0
		if s.walkable_at(p) and s.walkable_at(at.lerp(p, 0.5)) and s.walkable_at(p + (p - at).normalized() * 300.0):
			spot = p
			break
	check(spot != Vector2.INF, "an open spot near you")
	var foe: Node2D = s._spawn_npc(spot, 3, spot, "pirate")
	s.pilot.hp = s.pilot.max_hp
	var others := func() -> void:   # (everyone else - and anyone streamed in meanwhile)
		for n in foe.get_parent().get_children() + s.npcs:   # (an earlier test's citizens aren't in npcs)
			if n != foe and n != s.pilot and n.get("species") != null and n.is_processing():
				n.set_process(false)
				n.position += Vector2(0, 20000)
	others.call()
	await tree.process_frame
	foe._look = 99.0                       # (it hasn't noticed you: you're out of its reach anyway)
	# You shoot it: a real bolt, from you.
	var bolt := SurfaceProps.LaserBolt.new()
	bolt.position = at + Vector2(0, -60)
	bolt.target = foe
	bolt.shooter = s.pilot
	bolt.damage = 10.0
	bolt.accuracy = 1.0   # (a sure shot: what it does when hit is the point here)
	foe.get_parent().add_child(bolt)
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(bolt) and Time.get_ticks_msec() - t0 < 2000:
		await tree.process_frame
	check(foe.hp < foe.max_hp, "the bolt hit it")
	check(foe._avenge == s.pilot, "it knows who shot it")
	check(foe._state in ["chase", "raise"], "it turns on you at once (%s)" % foe._state)
	# It closes in and fires back.
	var fired_at_you := false
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 9000 and not fired_at_you:
		await tree.process_frame
		others.call()
		fired_at_you = foe._state == "fire" and foe._aim_at == s.pilot
	check(fired_at_you, "it fires back at you")
	check(foe.position.distance_to(s.pilot.position) < SurfaceProps.SurfacePirate.RANGE * 1.15, "having closed in to its reach (%.0f px)" % foe.position.distance_to(s.pilot.position))
	# Badly hurt, it runs - rifle down, away from you.
	foe.hp = foe.max_hp * 0.25
	foe.attacked_by(s.pilot)
	check_eq(foe._state, "flee", "badly hurt: it runs")
	var d0: float = foe.position.distance_to(s.pilot.position)
	t0 = Time.get_ticks_msec()
	var shots_while_fleeing := 0
	while Time.get_ticks_msec() - t0 < 2000:
		await tree.process_frame
		others.call()
		if foe._state == "fire":
			shots_while_fleeing += 1
	check(foe.position.distance_to(s.pilot.position) > d0 + 120.0, "away from you (%.0f -> %.0f px)" % [d0, foe.position.distance_to(s.pilot.position)])
	check(foe._raise < 0.05, "rifle down while it runs")
	check_eq(shots_while_fleeing, 0, "and it doesn't shoot while running")
	check(SurfaceProps.SurfacePirate.FLEE_SPEED < s.pilot.speed, "you can run it down")
	# Far enough (or long enough): it stops there, and still won't pick a fight.
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000 and foe._state == "flee":
		await tree.process_frame
		others.call()
	check_eq(foe._state, "walk", "it stops running")
	check(foe.home.distance_to(foe.position) < 5.0, "and lies low where it stopped")
	s.pilot.position = foe.position + Vector2(-300, 0)
	foe._look = 0.0
	await tree.process_frame
	await tree.process_frame
	check_eq(foe._state, "flee", "you come near: hurt, it runs again rather than fight")


func test_player_attacks_enemies() -> void:
	var s: Node = await _surface("thalassa")
	for n in s.npcs.filter(func(n): return n.species == "pirate"):
		n.set_process(false)   # (only ours in this test: the others stand aside)
		n.position += Vector2(0, 20000)
	await tree.process_frame
	var at: Vector2 = s.pilot.position
	var foe: Node2D = s._spawn_npc(at + Vector2(1000, 120), 3, at + Vector2(1000, 120), "pirate")
	foe.set_process(false)   # (it stands still and doesn't shoot back here)
	await tree.process_frame
	var click := func(world: Vector2, button: MouseButton) -> void:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = true
		e.position = s.get_canvas_transform() * world
		s._unhandled_input(e)
	var hover := InputEventMouseMotion.new()
	hover.position = s.get_canvas_transform() * (foe.position + Vector2(0, -110))
	s._unhandled_input(hover)
	check(s._hovered == foe, "hovering an enemy (crosshair cursor)")
	# A click on its head (not just its middle) attacks it.
	click.call(foe.position + Vector2(10, -125), MOUSE_BUTTON_LEFT)
	check(s._attack_target == foe, "clicking an enemy attacks it")
	s.set_process(true)
	var t0 := Time.get_ticks_msec()
	var fired := false
	while Time.get_ticks_msec() - t0 < 20000 and is_instance_valid(foe) and not foe.dead:
		await tree.process_frame
		fired = fired or s.pilot.trigger == foe
	var t := (Time.get_ticks_msec() - t0) / 1000.0
	check(fired, "out of range: you closed in and opened fire")
	check(not is_instance_valid(foe) or foe.dead, "and it fell (%.1f s)" % t)
	await tree.process_frame
	await tree.process_frame
	check(s._attack_target == null, "the fight is over")
	# Right-click on another: attacks too; a click on the ground ends it.
	var foe2: Node2D = s._spawn_npc(s.pilot.position + Vector2(300, 0), 4, s.pilot.position + Vector2(300, 0), "pirate")
	foe2.set_process(false)
	await tree.process_frame
	s.set_process(false)
	click.call(foe2.position + Vector2(0, -20), MOUSE_BUTTON_RIGHT)
	check(s._attack_target == foe2, "right-click on an enemy attacks it too")
	click.call(s.pilot.position + Vector2(-200, 40), MOUSE_BUTTON_LEFT)
	check(s._attack_target == null and s.pilot.trigger == null, "a click on the ground ends the fight")
	var f := InputEventKey.new()
	f.keycode = KEY_F
	f.pressed = true
	s._unhandled_input(f)
	check(s._attack_target == foe2, "F attacks the nearest enemy")
	s.queue_free()
	await tree.process_frame


## Bolts are fast and homing: a target running away sideways
## (faster than you can walk) is still hit, quickly.
func test_shots_cannot_be_dodged() -> void:
	var host := Node2D.new()
	tree.root.add_child(host)
	for kind in ["bolt"]:
		var foe := Dummy.new()
		foe.position = Vector2(900, 0)
		host.add_child(foe)
		var shot: Node2D = SurfaceProps.LaserBolt.new()
		shot.target = foe
		shot.accuracy = 1.0   # (on target: a hit is rolled as it's fired - Accuracy; then it can't be dodged)
		host.add_child(shot)
		var t := 0.0
		var dt := 1.0 / 60.0
		while t < 1.5 and foe.hits == 0:
			foe.position += Vector2(0, 600.0 * dt) * (1.0 if int(t * 4.0) % 2 == 0 else -1.0)   # dodging, zig-zag
			shot._process(dt)
			t += dt
		check(foe.hits == 1, "%s: a target running and zig-zagging is still hit" % kind)
		check(t < 0.5, "%s: and quickly (%.2f s over 900 px)" % [kind, t])
	# A miss is rolled as it's fired: aimed past the target, it flies on by.
	var misses := 0
	for i in 20:
		var foe2 := Dummy.new()
		foe2.position = Vector2(700, 0)
		host.add_child(foe2)
		var shot2: Node2D = SurfaceProps.LaserBolt.new()
		shot2.target = foe2
		shot2.accuracy = 0.0
		host.add_child(shot2)
		for k in 60:
			if is_instance_valid(shot2):
				shot2._process(1.0 / 60.0)
		if foe2.hits == 0:
			misses += 1
		foe2.queue_free()
	check(misses >= 15, "a hopeless shot misses: it flies past (%d of 20)" % misses)
	host.queue_free()
	await tree.process_frame


func test_guard_shoots_hostiles() -> void:
	var s: Node = await _surface("thalassa")
	var g: Node = null
	for a in s.npcs:
		if a.species == "gunner":
			g = a
	check(g != null, "a Minoan guard on the surface")
	if g == null:
		return
	var foe := Dummy.new()
	foe.position = g.position + Vector2(300, 0)
	foe.add_to_group("surface_hostiles")
	s.objects.add_child(foe)
	for i in 120:
		g._process(1.0 / 60.0)
		for b in s.objects.get_children():
			if b is SurfaceProps.LaserBolt:
				b._process(1.0 / 60.0)
		if g._state == "fire":
			check(g.puppet.raise_amt > 0.9, "the rifle is shouldered while firing")
		await tree.process_frame
	check(foe.hits > 0, "the guard hit the hostile (%d hits)" % foe.hits)
	foe.queue_free()
	s.queue_free()
	await tree.process_frame


class Dummy extends Node2D:
	var hits := 0
	func surface_hit(_d: float, _dtype := "") -> void:
		hits += 1


## The Minoan androids (tools/android_sheets.py): drawn from their sheets in
## all 8 views (every pose), the rifle firing bolts and the bow arrows at a
## hostile, the labrys striding up to it and cleaving it.
func test_android_citizens() -> void:
	var host := Node2D.new()
	tree.root.add_child(host)
	for kind in ["android", "android_bow", "android_axe"]:
		var a: Node2D = SurfaceProps.citizen(kind, 1)
		host.add_child(a)
		await tree.process_frame
		check(a is SurfaceProps.MinoanAndroid and a.puppet is SheetPuppet, "%s: an android drawn from sprite sheets" % kind)
		check(a.npc_name in SurfaceProps.MinoanAndroid.ANDROID_NAMES, "%s: named for the automata of Crete (%s)" % [kind, a.npc_name])
		var sp: SheetPuppet = a.puppet
		check_eq(sp.sequence, ["idle", "raise1", "aim"] if kind == "android_axe" else ["idle", "aim"], kind + ": its poses")
		for pose in sp.sequence:
			for d in SheetPuppet.DIRS:
				check(ResourceLoader.exists("res://art/%s/%s_%s_%s.png" % [sp.rig_id, sp.rig_id, pose, d]), "%s: %s %s" % [kind, pose, d])
		var foe := Dummy.new()
		foe.position = a.position + Vector2(300, 0)
		host.add_child(foe)
		a.watch = foe
		var shots := 0
		for i in 400:
			a._process(1.0 / 60.0)
			for c in host.get_children():
				if c is SurfaceProps.LaserBolt:
					shots += 1
					check(c.texture == ProcArt.get_tex("fx_android_arrow" if kind == "android_bow" else "fx_android_bolt"), kind + ": its own shot")
					c.queue_free()
			if foe.hits > 0 or shots > 0:
				break
			await tree.process_frame
		if kind == "android_axe":
			check(foe.hits > 0, "the labrys android closes in and cleaves (%.0f px away)" % a.position.distance_to(foe.position))
			check(shots == 0, "no shots")
		else:
			check(shots > 0, kind + ": fires at a hostile in range")
		a.queue_free()
		foe.queue_free()
	for k in ["arrow", "arrow_impact", "bow_flash", "bolt", "bolt_impact", "slash", "shockwave", "axe_sparks"]:
		check(ProcArt.has_sprite("fx_android_" + k), "the effect " + k)
	host.queue_free()
	await tree.process_frame


## Kilon Alios stands by the landing pad on Amnissos (only there), drawn
## from his 8-view sheet, a quest bulb over his head; talking to him offers
## the main quest (his portrait in the dialogue box), accepting starts it in
## the state you take back to space.
func test_quest_giver_on_thalassa() -> void:
	SaveGame.space_state = {}
	var kry: Node = await _surface("krystallos")   # (visited first: he's there too - every world has him)
	check(kry.quest_giver != null and not kry.quest_giver.offering, "Kilon on Ida too, without the quest's sign (that's on Amnissos)")
	kry.queue_free()
	await tree.process_frame
	var s: Node = await _surface("thalassa")
	var g: Node2D = s.quest_giver
	check(g != null, "Kilon Alios is on Amnissos")
	if g == null:
		return
	check_eq(g.npc_name, "Kilon Alios", "his name")
	check(g.position.distance_to(s.lander.position) < 450.0, "next to the landing site")
	check(g.puppet is SheetPuppet and g.puppet._sprite.texture.resource_path.contains("kilon_idle_"), "drawn from his sprite sheet")
	for d in SheetPuppet.DIRS:
		check(ResourceLoader.exists("res://art/kilon/kilon_idle_%s.png" % d), "his %s view" % d)
	check(g.bulb != null and g.bulb.visible, "a quest bulb over his head")
	check(g.bulb.position.y < -g.HEIGHT, "above his head")
	# He turns to you.
	s.pilot.position = g.position + Vector2(200, 0)
	g._process(0.016)
	check_eq(g.puppet._view, "e", "he turns to face you")
	# Talking: his greeting, with his portrait, then the questions you can ask.
	g.interact(s)
	var box: Control = s.dialogue_box()
	check(box.is_open(), "the conversation opens")
	check(box._speaker.text == "Kilon Alios" and box._portrait_box.visible and box._portrait.texture != null, "with his portrait")
	box._finish()   # (the greeting read: the menu of questions)
	await tree.process_frame
	for ask in ["Who are you?", "Who am I?", "Where am I?", "What is my mission?", "What should I become?", str(QuestData.GIVER["quest_ask"]), "Farewell"]:
		check(_button(s, ask) != null, "you can ask him: " + ask)
	# Who is he? The maintainer of this world, under Ephestos - then the menu again.
	_button(s, "Who are you?").pressed.emit()
	await tree.process_frame
	check(box.is_open() and str(box._lines[0][1]).contains("maintainer of this world") and str(box._lines[1][1]).contains("Ephestos"), "who he is: the maintainer, under Ephestos")
	box._finish()
	await tree.process_frame
	check(_button(s, "Who am I?") != null, "his answer done: the questions again")
	_button(s, "Who am I?").pressed.emit()
	await tree.process_frame
	check(str(box._lines[0][1]).contains("automaton, built by [b]Ephestos[/b]"), "who you are: an automaton built by Ephestos")
	box._finish()
	await tree.process_frame
	# The main quest, from the menu: his offer (Accept / Not now).
	_button(s, str(QuestData.GIVER["quest_ask"])).pressed.emit()
	await tree.process_frame
	check(box.is_open() and box._lines == QuestData.GIVER["offer"], "the signal: his offer")
	box._finish()
	await tree.process_frame
	check_eq(s.main_quest_stage(), -1, "nothing taken before you accept")
	s.accept_main_quest(g)
	check_eq(s.main_quest_stage(), 0, "accepting starts the main quest")
	check(not g.bulb.visible, "the bulb goes out once you've taken it")
	check(box.is_open() and box._lines.size() > QuestData.GIVER["accepted"].size(), "his reply, then the story's opening")
	box._finish()
	await tree.process_frame
	# Later he tells you where it leads (the quest's question, renamed).
	s._giver_quest(g)
	check(str(box._lines[-1][1]).contains(QuestData.STAGES[0]["objective"]), "talking again: where the thread leads now")
	box._finish()
	tree.paused = false
	s.queue_free()
	await tree.process_frame


## Clicking Kilon (the real mouse path): you walk up to him, the conversation
## starts, and it ends with the main quest's Accept / Not now.
func test_click_kilon_starts_the_conversation() -> void:
	SaveGame.space_state = {}
	var s: Node = await _surface("thalassa")
	var g: Node2D = s.quest_giver
	s.pilot.position = g.position + Vector2(260, 90)
	await tree.process_frame
	var hover := InputEventMouseMotion.new()
	hover.position = s.get_canvas_transform() * (g.position + Vector2(0, -60))
	s._unhandled_input(hover)
	check(s._hovered == g, "hovering him (his name shows)")
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	e.position = s.get_canvas_transform() * (g.position + Vector2(0, -60))
	s._unhandled_input(e)
	e = e.duplicate()
	e.pressed = false
	s._unhandled_input(e)
	s.set_process(true)
	var box: Control = s.dialogue_box()
	var t0 := Time.get_ticks_msec()
	while not box.is_open() and Time.get_ticks_msec() - t0 < 8000:
		await tree.process_frame
	check(box.is_open(), "clicking him: you walk over and the conversation starts")
	check_eq(box._speaker.text, "Kilon Alios", "he speaks")
	check(box._portrait_box.visible, "with his portrait")
	# His greeting read: the questions; the signal's brings the main quest's offer.
	for i in box._lines.size():
		box.advance()
	await tree.process_frame
	check(_button(s, "Who are you?") != null, "then the questions you can ask him")
	_button(s, str(QuestData.GIVER["quest_ask"])).pressed.emit()
	await tree.process_frame
	for i in box._lines.size():
		box.advance()
	await tree.process_frame
	var offered := false
	for c in s.get_children():
		if c is CanvasLayer and c.layer == 50 or (c is CanvasLayer and _has_text(c, str(QuestData.GIVER["quest_title"]))):
			offered = offered or _has_text(c, str(QuestData.GIVER["quest_title"]))
	check(offered, "then the main quest: Accept / Not now")
	tree.paused = false
	s.queue_free()
	await tree.process_frame


## A visible button whose text is `text` (the conversation's questions), or null.
func _button(n: Node, text: String) -> Button:
	for b in n.find_children("*", "Button", true, false):
		if b.text == text and b.is_inside_tree():
			return b
	return null


func _has_text(n: Node, text: String) -> bool:
	if (n is Label or n is Button) and n.text.contains(text):
		return true
	for c in n.get_children():
		if _has_text(c, text):
			return true
	return false


## Citizens flagged as quest givers carry the bulb too.
func test_citizen_quest_bulb() -> void:
	var c: Node2D = SurfaceProps.citizen("gunner", 0)
	c.quest_giver = true
	tree.root.add_child(c)
	await tree.process_frame
	check(c._bulb != null and c._bulb.visible, "a quest-giving citizen has a bulb")
	c.quest_giver = false
	check(not c._bulb.visible, "and loses it when they have nothing to give")
	c.queue_free()
	await tree.process_frame


## Every planet has at least two buildings, each at least 12 x 12 tiles, on
## levelled, walkable ground with no scenery inside.
func test_big_buildings_on_cleared_ground() -> void:
	for pid in Planets.PLANETS.keys().filter(func(p): return Planets.PLANETS[p].get("landable", false) and Planets.PLANETS[p].get("villages", true)):
		var s: Node = await _surface(pid)
		await s.stream_all()   # (the whole planet in: it streams, a chunk at a time)
		check(s.buildings.size() >= 2, "%s: at least two buildings (%d)" % [pid, s.buildings.size()])
		for b in s.buildings:
			var r: Rect2i = b.rect
			check(r.size.x >= 12 and r.size.y >= 12, "%s: %s is at least 12 x 12 (%s)" % [pid, b.title, r.size])
			var dry := true
			for i in range(r.position.x - 1, r.end.x + 1):
				for j in range(r.position.y - 1, r.end.y + 1):
					if not s.walkable_cell(Vector2i(i, j)):
						dry = false
			check(dry, "%s: %s stands on cleared ground" % [pid, b.title])
			var inside := 0
			for p in s._props:
				if is_instance_valid(p) and r.has_point(s.tilemap.local_to_map(p.position)):
					inside += 1
			check(inside == 0, "%s: no trees or rocks inside the %s (%d)" % [pid, b.title, inside])
		# Every plot planned across the planet (built when you come near) is levelled.
		var wet := 0
		for p in s._plans:
			var r: Rect2i = s._plan_rect(p)
			for i in range(r.position.x - 1, r.end.x + 1):
				for j in range(r.position.y - 1, r.end.y + 1):
					if not s.walkable_cell(Vector2i(i, j)):
						wet += 1
		check_eq(wet, 0, "%s: all %d planned plots on cleared ground" % [pid, s._plans.size()])
		s.queue_free()
		await tree.process_frame


## The planet is 440 x 440 tiles, built piece by piece: generated on a worker
## thread without blocking, only the area around you made, scenery chunks
## freed behind you and grown again (the same) when you come back, the path
## grid following you, and a far destination walked to leg by leg.
func test_streamed_planet() -> void:
	SaveGame.landed_planet = "selene"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	var worst := 0.0
	var last := Time.get_ticks_usec()
	while not s.is_built:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
	check_eq(s.N, 440, "the surface is 440 x 440 tiles")
	# (alone a frame takes under 100 ms; tools/test.py runs 12 Godots at once, sharing the CPU)
	check(worst < 400.0, "building it never blocks a frame long (worst %.0f ms)" % worst)
	check(s._plans.size() >= 8, "villages planned all over the planet (%d buildings)" % s._plans.size())
	var spread := Rect2i(s._plan_rect(s._plans[0]).get_center(), Vector2i.ZERO)
	for p in s._plans:
		spread = spread.expand(s._plan_rect(p).get_center())
		var r: Rect2i = s._plan_rect(p)
		check(r.size.x >= 12 and r.size.y >= 12, "every planned building is at least 12 x 12")
	check(spread.size.x > 120 and spread.size.y > 120, "spread across the planet (%s)" % spread.size)
	check(s.buildings.size() < s._plans.size() and s.npcs.size() < s._npc_plans.size(), "only what's near you is built (%d of %d buildings)" % [s.buildings.size(), s._plans.size()])
	check(s._chunks.size() <= 25, "scenery only around you (%d chunks)" % s._chunks.size())
	# Remember a chunk's scenery, walk away (it's freed), come back (the same again).
	var here: Vector2i = s._chunk_of(s._cell_at(s.pilot.position))
	var before := _chunk_sig(s, here)
	check(before.size() > 0, "the chunk you stand in has scenery")
	var home: Vector2 = s.pilot.position
	s.set_process(true)
	s.pilot.position = s._cell_pos(s._cell_at(home) + Vector2i(150, 0))
	for i in 200:
		await tree.process_frame
	var tw := Time.get_ticks_msec()   # (under load the path grid's worker may still be at it)
	while (s._nav_task >= 0 or s._nav_dirty) and Time.get_ticks_msec() - tw < 8000:
		await tree.process_frame
	check(not s._chunks.has(here), "a chunk far behind you is freed")
	check(s._cell_at(s.pilot.position) - s._nav_origin == (s._cell_at(s.pilot.position) - s._nav_origin).clamp(Vector2i(8, 8), Vector2i(s.NAV_WIN - 8, s.NAV_WIN - 8)), "the path grid followed you")
	s.pilot.position = home
	var t0 := Time.get_ticks_msec()
	while not s._chunks.has(here) or not s._place_queue.is_empty() or not s._chunk_tasks.is_empty():
		await tree.process_frame
		if Time.get_ticks_msec() - t0 > 8000:
			break
	check(_chunk_sig(s, here) == before, "it grows back the same when you return")
	# A destination far beyond the grid: walked to leg by leg.
	var t1 := Time.get_ticks_msec()
	while s._nav_task >= 0 and Time.get_ticks_msec() - t1 < 8000:
		await tree.process_frame
	var far: Vector2 = s._cell_pos(s._cell_at(home) + Vector2i(0, 120))
	s._walk_to(far)
	check(s._far_goal == far, "a far destination becomes the goal")
	check(not s.pilot.path.is_empty(), "the first leg is under way")
	# A saved layout keeps every building (built or not) and only hand-placed scenery.
	var lay: Dictionary = s.get_layout()
	check_eq(lay["buildings"].size(), s._plans.size(), "the layout keeps every planned building")
	check(lay["props"].is_empty(), "the planet's own scenery isn't saved (it grows back)")
	s.queue_free()
	await tree.process_frame


func _chunk_sig(s: Node, key: Vector2i) -> Array:
	var out := []
	for p in s._props:
		if not is_instance_valid(p):
			continue
		var k: Vector2i = p.get_meta("chunk", Vector2i(-9, -9)) if p is Node else p.chunk
		if k == key:
			out.append("%s %d %d" % [p.kind, roundi(p.position.x), roundi(p.position.y)])
	out.sort()
	return out


func test_upper_floors_and_stairs() -> void:
	var s: Node = await _surface("thalassa")
	var ups: Array = s.buildings.filter(func(b): return b.upper != null)
	check(ups.size() >= 2, "buildings with an upper floor (%d)" % ups.size())
	for b in ups:
		var f = b.upper
		check(not s.walkable_at(s._cell_pos(f.stair_0)), "%s: the staircase blocks the ground floor" % b.title)
		check(s.walkable_at(s._cell_pos(f.stair_a)), "%s: the stairs can be approached" % b.title)
		# Walk to the stairs from outside and climb.
		s.pilot.position = s.lander.position + Vector2(0, 120)
		s._target_thing = f.up_thing
		s._walk_to(f.up_thing.approach())
		for i in 1500:
			s._process(DT)
			s.pilot._process(DT)
			for d in s.all_doors():
				d._process(DT)
			if s.level == 1 and not s._climbing:
				break
			await tree.process_frame
		check_eq(s.level, 1, "%s: climbed the stairs" % b.title)
		if s.level != 1:
			continue
		# Walk into the upper room and back to the stairwell, then down.
		var room_c: Vector2 = s._cell_pos(f.room.get_center())
		var p: PackedVector2Array = s._p_path(s.pilot.position, room_c)
		check(not p.is_empty() and p[-1].distance_to(room_c) < 20.0, "%s: a route into the upper room" % b.title)
		var back: PackedVector2Array = BuildingFloors.path(s, b, room_c, s._cell_pos(f.landing))
		check(not back.is_empty() and back[-1].distance_to(s._cell_pos(f.landing)) < 20.0, "%s: and back to the stairs" % b.title)
		s.climb(b, false)
		var t0 := Time.get_ticks_msec()
		while s._climbing and Time.get_ticks_msec() - t0 < 6000:   # (the climb plays in real time)
			await tree.process_frame
		check_eq(s.level, 0, "%s: back down" % b.title)
	s.queue_free()
	await tree.process_frame


func test_routes_take_the_stairs() -> void:
	var s: Node = await _surface("thalassa")
	var ups: Array = s.buildings.filter(func(b): return b.upper != null)
	if not check(not ups.is_empty(), "a building with an upper floor"):
		return
	var b = ups[0]
	var goal: Vector2 = s._cell_pos(b.upper.room.get_center())
	s.pilot.position = s.lander.position + Vector2(0, 120)
	s._route_to([goal, 1, b])     # from outside to the upper room
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and not (s.level == 1 and not s._climbing and s.pilot.position.distance_to(goal) < 12.0):
		s._process(DT)
		s.pilot._process(DT)
		for d in s.all_doors():
			d._process(DT)
		await tree.process_frame
	check_eq(s.level, 1, "the route climbed the stairs")
	check(s.pilot.position.distance_to(goal) < 12.0, "and reached the spot upstairs")
	var out: Vector2 = s.lander.position + Vector2(0, 120)
	s._route_to([out, 0, null])   # and back out: down the stairs first
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 30000 and not (s.level == 0 and not s._climbing and s.pilot.position.distance_to(out) < 12.0):
		s._process(DT)
		s.pilot._process(DT)
		for d in s.all_doors():
			d._process(DT)
		await tree.process_frame
	check_eq(s.level, 0, "the route went down the stairs")
	check(s.pilot.position.distance_to(out) < 12.0, "and walked out to the spot")
	s.queue_free()
	await tree.process_frame


## The pirate's sounds (sounds/pirate/, tools/sfx_pirate.py) and Sfx playing them.
func test_pirate_sounds() -> void:
	var sfx: Node = tree.root.get_node("Sfx")
	var takes := {"shot": 4, "raise": 2, "lower": 2, "step": 6, "hurt": 4, "death": 2, "taunt": 4, "flee": 2,
		"bolt_hit": 3, "loot_drop": 1, "loot_take": 1}
	for k in takes:
		var list: Array = sfx.takes("pirate/" + k)
		check_eq(list.size(), takes[k], "pirate/%s: every take found" % k)
		for st in list:
			check(st is AudioStream and st.get_length() > 0.1 and st.get_length() < 2.5, "pirate/%s: a short sound" % k)
	check(sfx.takes("pirate/nonexistent").is_empty(), "an unknown sound: no takes (and no error)")
	check(AudioServer.get_bus_index("SFX") >= 0, "the SFX bus")
	var holder := Node2D.new()
	tree.root.add_child(holder)
	var pl = sfx.play_at("pirate/shot", Vector2(10, 20), holder)
	check(pl is AudioStreamPlayer2D and pl.bus == "SFX" and pl.position == Vector2(10, 20), "a sound plays in the world, on the SFX bus")
	for i in 20:
		sfx.play_at("pirate/step", Vector2.ZERO, holder)
	var steps := holder.get_children().filter(func(c): return c is AudioStreamPlayer2D and c.stream in sfx.takes("pirate/step"))
	check(steps.size() <= sfx.MAX_EACH, "one sound doesn't pile up (%d at once)" % steps.size())
	# The volume setting drives the bus.
	var old: float = Settings.sfx_volume
	Settings.set_sfx_volume(0.5)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")) - linear_to_db(0.5)) < 0.01, "the volume setting sets the SFX bus")
	Settings.set_sfx_volume(0.0)
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("SFX")), "0% mutes the effects")
	Settings.set_sfx_volume(old)
	for c in holder.get_children():
		c.free()
	# A pirate makes them: firing, raising the rifle, being hit, falling.
	var props = load("res://scripts/surface_props.gd")
	var p: Node2D = props.citizen("pirate", 1)
	holder.add_child(p)
	var target := Node2D.new()
	target.position = Vector2(300, 0)
	holder.add_child(target)
	for i in 3:
		await tree.process_frame
	p.set_process(false)
	var heard := func(name: String) -> bool:
		return holder.get_children().any(func(c): return c is AudioStreamPlayer2D and c.stream in sfx.takes("pirate/" + name))
	p._aim_at = target
	p._shoot()
	check(heard.call("shot"), "a pirate's shot is heard")
	p._go("raise")
	check(heard.call("raise"), "and its rifle coming up")
	p.surface_hit(5.0)
	check(heard.call("hurt"), "and its grunt when hit")
	p.surface_hit(500.0)
	check(heard.call("death"), "and its fall")
	holder.queue_free()
	await tree.process_frame


## Hot reload: the buildings' pieces (walls, floors, roofs, crowns, columns,
## decor) are tagged with how they were made, so changed tile pictures or
## building styles redo every building's textures in place (LiveLink).
func test_buildings_hot_reload() -> void:
	var s: Node = await _surface("thalassa")
	var tagged := []
	var stack: Array = [s]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is Sprite2D and n.has_meta(MinoanTiles.SKIN):
			tagged.append(n)
	var kinds := {}
	for t in tagged:
		kinds[t.get_meta(MinoanTiles.SKIN)[0]] = true
	check(tagged.size() > 100, "the buildings' pieces are tagged (%d)" % tagged.size())
	for k in ["wall", "roof", "piece", "decor"]:
		check(kinds.has(k), "%s pieces are tagged" % k)
	check(not s._minoan_floors.is_empty(), "and the floor tiles")
	# A wall's picture changes (as if its tile PNG were re-cut): red.
	var w: Sprite2D = tagged.filter(func(t): return t.get_meta(MinoanTiles.SKIN)[0] == "wall")[0]
	var how: Array = w.get_meta(MinoanTiles.SKIN)
	var piece: String = MinoanTiles._wall_piece(MinoanTiles._wall_design(how[2], how[3], how[4]), how[1])
	var before: Texture2D = w.texture
	var src: Image = MinoanTiles.image(piece)
	MinoanTiles.hot_reload([piece])
	var red := Image.create(src.get_width(), src.get_height(), false, Image.FORMAT_RGBA8)
	red.fill(Color(1, 0, 0, 1))
	MinoanTiles._img[piece] = red
	var n_done: int = s.reskin_buildings()
	check(n_done >= tagged.size(), "every piece redone (%d)" % n_done)
	check(w.texture != before, "the wall has a new texture")
	var img := w.texture.get_image()
	var c := img.get_pixel(img.get_width() / 2, img.get_height() * 3 / 4)
	check(c.r > 0.9 and c.g < 0.1, "showing the new picture (%s)" % c)
	# Back as it was; and LiveLink's own path (a tile PNG reported changed).
	MinoanTiles._fresh.clear()
	MinoanTiles.forget()
	s.reskin_buildings()
	var seq: int = LiveLink._seq
	LiveLink._rebuild_buildings(["res://data/sprites/tile_%s.png" % piece], [])
	check(LiveLink.events_since(seq).any(func(e): return e["text"].begins_with("buildings: 1 tile picture")), "LiveLink reskins the buildings when a tile PNG changes")
	var c2 := w.texture.get_image().get_pixel(img.get_width() / 2, img.get_height() * 3 / 4)
	check(not (c2.r > 0.9 and c2.g < 0.1), "and the wall shows its PNG again")
	MinoanTiles._fresh.clear()
	MinoanTiles.forget()
	s.queue_free()


## Upper floors are furnished too: pieces along the upper room's walls (at
## least one container), blocking the way upstairs, clickable and openable
## from up there - with keys of their own.
func test_upper_floor_furniture() -> void:
	var s: Node = await _surface("thalassa")
	var ups: Array = s.buildings.filter(func(b): return b.upper != null)
	check(not ups.is_empty(), "buildings with an upper floor (%d)" % ups.size())
	var total := 0
	for b in ups:
		var f = b.upper
		total += f.furniture.size()
		check(f.furniture.any(func(p): return p.is_container()), "a container upstairs in %s" % b.title)
		for p in f.furniture:
			check(p.get_parent() == f.node, "drawn on the upper floor (a storey up)")
			check(p.key.ends_with("^"), "its own key (%s)" % p.key)
			if not p.is_flat():
				check(not BuildingFloors.walkable(s, b, p.position, 6.0), "it blocks the way upstairs")
			check(f.room.has_point(p.cell), "inside the upper room")
	check(total >= ups.size() * 2, "furnished: %d pieces on %d upper floors" % [total, ups.size()])
	# Upstairs, a chest is there to click and open.
	var b = ups[0]
	var chest = b.upper.furniture.filter(func(p): return p.is_container())[0]
	s._set_level(1, b)
	s.pilot.position = chest.approach()
	check(s._thing_at(chest.click_center() - Vector2(0, s.lift_at(chest.global_position))) == chest, "clickable from upstairs")
	check(s.pilot.position.distance_to(s._ground_of(chest)) < s.INTERACT_RANGE + 40.0, "within reach where you stand to open it")
	s.open_container(chest)
	check(chest.opened, "it opens")
	s._set_level(0, null)
	s.queue_free()


## Teleport gates across the planet: by the pad, by the villages and in the
## wilds, apart and on open ground; built when near; a gate opens the portal
## network's map, and a gate picked there takes you to it.
func test_teleport_gates() -> void:
	var s: Node = await _surface("thalassa")
	await s.stream_all()   # (the whole planet in: it streams, a chunk at a time)
	var gs: Array = s.gates
	check(gs.size() >= 6, "gates across the planet (%d)" % gs.size())
	var center := Vector2(s.N / 2, s.N / 2)
	check(gs.any(func(g): return Vector2(g["cell"]).distance_to(center) < 20.0), "one by the landing pad")
	for i in gs.size():
		for j in range(i + 1, gs.size()):
			check(Vector2(gs[i]["cell"]).distance_to(Vector2(gs[j]["cell"])) >= s.GATE_APART, "gates apart")
		check(s.walkable_at(s._cell_pos(gs[i]["cell"]) + Vector2(0, 70)), "%s: you can stand in front of it" % gs[i]["name"])
	var names := {}
	for g in gs:
		names[g["name"]] = true
	check_eq(names.size(), gs.size(), "every gate has its own name")
	# The pad's gate stands; clicking it opens the network's map.
	var pad := gs.filter(func(g): return g["node"] != null)
	check(not pad.is_empty(), "the gate near you is built")
	var gate: TeleportGate = pad[0]["node"]
	check(gate.get_child_count() > 0 and gate.get_child(0) is Sprite2D and gate.get_child(0).texture != null, "drawn from the portal tile")
	check(s._thing_at(gate.click_center() - Vector2(0, s.lift_at(gate.global_position))) == gate, "clickable (where it's drawn)")
	s.open_gate_map(gate)
	check(s.surface_map.visible and s.surface_map.gates_from == gate.index, "the portal network's map opens")
	var view = s.surface_map._view
	await tree.process_frame
	var far := -1
	for i in gs.size():
		if i != gate.index and (far < 0 or Vector2(gs[i]["cell"]).distance_to(center) > Vector2(gs[far]["cell"]).distance_to(center)):
			far = i
	# Undiscovered gates (under the fog of war) aren't on the map and can't be reached.
	if s.fog != null:
		check(not s.fog.explored(Vector2(gs[far]["cell"]) + Vector2(0.5, 0.5)), "the far gate is still under the fog")
		check(not view.gate_known(far) and view.gate_at(view.gate_pos(far)) == -1, "an undiscovered gate isn't on the map")
		check(view.gate_known(gate.index), "the gate you're at is")
		var before: Vector2 = s.pilot.position
		s.teleport_to(far)
		check(s.pilot.position == before, "and you can't travel to it")
		s.fog.reveal(Vector2(gs[far]["cell"]) + Vector2(0.5, 0.5), 12.0)   # (discovered)
	check(view.gate_known(far), "once discovered, it's on the map")
	check_eq(view.gate_at(view.gate_pos(far)), far, "a gate's marker picks it")
	view._walk(view.gate_pos(far))
	check(not s.surface_map.visible, "the map closes")
	check(s.pilot.position.distance_to(s._cell_pos(gs[far]["cell"])) < 120.0, "you step out at %s" % gs[far]["name"])
	for k in 30:
		s._stream_plans()
		await tree.process_frame
	check(gs[far]["node"] != null, "and its gate stands there")
	s.queue_free()


## The map opens even when it was built before its header labels existed (a
## hot reload of surface_map.gd while the game runs).
func test_map_opens_without_its_labels() -> void:
	var s: Node = await _surface("thalassa")
	s.surface_map.open()
	s.surface_map.close()
	s.surface_map._title = null
	s.surface_map._hint = null
	s.surface_map.open()
	check(s.surface_map.visible, "the map still opens")
	s.surface_map.close()
	s.queue_free()


## Dying on the surface: back beside your ship at full health - and the fog of
## war as it was (what you'd explored stays explored, and is stored).
func test_death_keeps_the_fog() -> void:
	var s: Node = await _surface("thalassa")
	var far: Vector2 = Vector2(s.N / 2 + 150, s.N / 2 + 40)
	s.fog.reveal(far, 20.0)
	var share: float = s.fog.explored_share()
	check(s.fog.explored(far), "explored far from the ship")
	s.pilot.position = s._cell_pos(Vector2i(far))
	s.pilot.surface_hit(1000.0)
	check(s.pilot.position.distance_to(s.lander.position) < 150.0 and s.pilot.hp == s.pilot.max_hp, "back beside the ship, healed")
	check(s.fog.explored(far) and is_equal_approx(s.fog.explored_share(), share), "the fog of war is as it was")
	var stored := FogOfWar.new(s.N / s.FOG_CELL, s.N / s.FOG_CELL, Vector2.ZERO, float(s.FOG_CELL))
	stored.load_from(str(s.state["planets"][s.planet_id].get("explored", "")))
	check(stored.explored(far), "and stored with the planet")
	s.queue_free()


## The ledges' cliffs block exactly where they're drawn: every point where the
## ground climbs a wall's worth (and isn't a ramp) is unwalkable.
func test_cliffs_block_where_drawn() -> void:
	for pid in PLANETS:
		var s: Node = await _surface(pid)
		var T = s.TERRAIN
		var N: int = s.N
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		var walls := 0
		var open := 0
		for k in 12000:
			var g := Vector2(rng.randf_range(N * 0.3, N * 0.7), rng.randf_range(N * 0.3, N * 0.7))
			var x0 := floori(g.x)
			var y0 := floori(g.y)
			var fx := g.x - x0
			var fy := g.y - y0
			var rp: float = lerpf(lerpf(s._ramp[x0 * N + y0], s._ramp[(x0 + 1) * N + y0], fx), lerpf(s._ramp[x0 * N + y0 + 1], s._ramp[(x0 + 1) * N + y0 + 1], fx), fy)
			if rp >= 0.45:
				continue
			if s._tiled:   # (ramps climb a level a tile: ways up, not walls)
				var on_ramp := false
				for q in [g, g + Vector2(0.12, 0), g + Vector2(0, 0.12)]:
					if s._rampd[clampi(roundi(q.x), 0, N - 1) * N + clampi(roundi(q.y), 0, N - 1)] != 0:
						on_ramp = true
				if on_ramp:
					continue
			var e0: float = s.lift_at(s._g2w * g)
			var ex: float = (s.lift_at(s._g2w * (g + Vector2(0.12, 0))) - e0) / 0.12
			var ey: float = (s.lift_at(s._g2w * (g + Vector2(0, 0.12))) - e0) / 0.12
			if maxf(absf(ex), absf(ey)) >= T.CLIFF_PX * 1.15:
				walls += 1
				if s._ground_ok(s._g2w * g):
					open += 1
		check_eq(open, 0, "%s: cliff points walkable (of %d)" % [pid, walls])
		s.queue_free()
		await tree.process_frame


## Nobody shoots through a wall: no clear line across one (a doorway is), and
## a bolt fired at someone behind a wall bursts on it.
func test_no_shooting_through_walls() -> void:
	var s: Node = await _surface("thalassa")
	var b = s.buildings[0]
	var seg: Array = b.segments[0]
	var mid: Vector2 = (seg[0] + seg[1]) * 0.5
	var nrm: Vector2 = (seg[1] - seg[0]).orthogonal().normalized()
	var a: Vector2 = mid + nrm * 40.0
	var z: Vector2 = mid - nrm * 40.0
	check(not s.shot_clear(a, z), "no line of fire across a wall")
	check(s.shot_clear(a, a + (seg[1] - seg[0]).normalized() * 30.0), "a line along it is clear")
	# A bolt at a target behind the wall stops at it.
	var foe := Node2D.new()
	foe.position = z
	s.objects.add_child(foe)
	var bolt = s.PROPS.LaserBolt.new()
	bolt.shooter = s.pilot
	bolt.target = foe
	bolt.position = a - Vector2(0, bolt.GROUND)
	s.objects.add_child(bolt)
	for k in 30:
		if not is_instance_valid(bolt):
			break
		bolt._process(1.0 / 60.0)
		if is_instance_valid(bolt) and bolt.is_queued_for_deletion():
			break
	check(not is_instance_valid(bolt) or bolt.is_queued_for_deletion(), "the bolt burst on the wall")
	check(is_instance_valid(bolt) == false or (bolt.position + Vector2(0, bolt.GROUND)).distance_to(z) > 30.0, "short of the target")
	s.queue_free()


## The surface map doesn't pause; clicking it walks you there with the map
## still open (the route on it); a hit closes it.
func test_surface_map_runs_and_closes_on_attack() -> void:
	var s: Node = await _surface("thalassa")
	s.set_process(true)
	s.surface_map.open()
	check(s.surface_map.visible and not tree.paused, "the map is open and the game goes on")
	var view = s.surface_map._view
	var goal: Vector2 = s._nearest_walkable(s.pilot.position + Vector2(400, 0))
	var at: Vector2 = view._grid_xform() * (view._world_to_grid * goal + Vector2(0.5, 0.5))   # (to_world's inverse)
	view._walk(at)
	check(s.surface_map.visible, "clicking keeps the map open")
	for k in 40:
		await tree.process_frame
	check(s.pilot.moving or s.pilot.position.distance_to(goal) < 30.0, "walking there with the map open")
	s.pilot.surface_hit(1.0)
	check(not s.surface_map.visible, "a hit closes the map")
	s.queue_free()


## Wildlife (SurfaceCreature): every forest animal has its four poses; Amnissos
## plans herds of all of them, those near you come out and far ones go; a wolf
## goes for you and bites, falls to your shots; a shy goat runs from you, the
## tortoise hides; the moon has none.
func test_forest_wildlife() -> void:
	for set_id in SurfaceCreature.FAUNA:
		for row in SurfaceCreature.FAUNA[set_id]:
			check(SurfaceCreature.SPECIES.has(row[0]), "%s is a species" % row[0])
			for p in SurfaceCreature.POSES:
				check(ProcArt.has_sprite("creature_%s_%s_%s" % [set_id, row[0], p]), "sprite %s %s %s" % [set_id, row[0], p])
	var s: Node = await _surface("thalassa")
	await s.stream_all()   # (the whole planet in: it streams, a chunk at a time)
	var kinds := {}
	for f in s._fauna_plans:
		kinds[f["species"]] = true
		check(s._ground_ok(f["pos"]), "%s planned on open ground" % f["species"])
	check(kinds.size() == SurfaceCreature.FAUNA["fo"].size(), "every forest species lives on Amnissos (%d)" % kinds.size())
	check(s._fauna_plans.size() > 150, "plenty of animals (%d)" % s._fauna_plans.size())
	for c in s.creatures:
		check(s._cell_at(c.position).distance_to(s._cell_at(s.pilot.position)) <= s.FAUNA_OUT, "only nearby ones are out")
	# Far away: the ones out go, the ones there come.
	var was: int = s.creatures.size()
	var far: Vector2 = s._nearest_walkable(s.pilot.position + Vector2(20000, 0))
	s.pilot.position = far
	s._stream_fauna()
	await tree.process_frame
	check(s.creatures.all(func(c): return is_instance_valid(c) and s._cell_at(c.position).distance_to(s._cell_at(far)) <= s.FAUNA_OUT), "the near ones are out (%d, %d before)" % [s.creatures.size(), was])
	# A wolf beside you: it bites.
	var spot: Vector2 = s._nearest_walkable(s.pilot.position + Vector2(140, 0))
	var wolf := SurfaceCreature.make("wolf")
	wolf.surface = s
	wolf.position = spot
	wolf.home = spot
	s.objects.add_child(wolf)
	s.creatures.append(wolf)
	check(wolf.is_in_group("surface_hostiles"), "wolves are hostile")
	var hp0: float = s.pilot.hp + s.pilot.shield   # (health and shield: a hit takes the shield first)
	for k in 240:
		wolf._process(1.0 / 60.0)
	check(wolf._state in ["chase", "bite"], "the wolf hunts you (%s)" % wolf._state)
	check(s.pilot.hp + s.pilot.shield < hp0, "and bites (%.0f -> %.0f)" % [hp0, s.pilot.hp + s.pilot.shield])
	# Shot: it falls (and stays gone).
	for k in 10:
		wolf.surface_hit(14.0)
	check(wolf.dead and not wolf.is_in_group("surface_hostiles"), "the wolf falls")
	# A goat runs from you; a tortoise hides.
	var goat := SurfaceCreature.make("goat")
	goat.surface = s
	goat.position = s._nearest_walkable(s.pilot.position + Vector2(-120, 0))
	goat.home = goat.position
	s.objects.add_child(goat)
	var g0: Vector2 = goat.position
	for k in 60:
		goat._process(1.0 / 60.0)
	check(goat._state == "flee" and goat.position.distance_to(s.pilot.position) > g0.distance_to(s.pilot.position), "the goat runs off")
	var tort := SurfaceCreature.make("tortoise")
	tort.surface = s
	tort.position = s._nearest_walkable(s.pilot.position + Vector2(0, 60))
	s.objects.add_child(tort)
	for k in 30:
		tort._process(1.0 / 60.0)
	check(tort._state == "hide" and tort._pose == 3, "the tortoise hides in its shell")
	s.queue_free()
	# The ice planets have their own crystal beasts.
	var m: Node = await _surface("selene")
	var ice := SurfaceCreature.FAUNA["ic"].map(func(r): return r[0])
	check(not m._fauna_plans.is_empty() and m._fauna_plans.all(func(f): return f["species"] in ice), "the ice moon has only ice creatures (%d)" % m._fauna_plans.size())
	for c in m.creatures:
		check(c._tex[0] != null, "%s has its picture" % c.species)
	m.queue_free()


## You fight animals like pirates: click one (attack) and you walk up and fire until it falls.
func test_you_can_kill_a_predator() -> void:
	var s: Node = await _surface("thalassa")
	s.set_process(true)
	for kind in ["boar", "snake", "wolf"]:
		var w := SurfaceCreature.make(kind)
		w.surface = s
		w.position = s._nearest_walkable(s.pilot.position + Vector2(300, 0))
		w.home = w.position
		s.objects.add_child(w)
		s.creatures.append(w)
		await tree.process_frame
		s.pilot.hp = s.pilot.max_hp
		var at: Vector2 = s.get_viewport().get_canvas_transform() * (w.position - Vector2(0, s.lift_at(w.position) + 20))
		check(s._hostile_at(s.get_canvas_transform().affine_inverse() * at) == w, "%s: under the cursor" % kind)
		s.attack(w)
		var t := 0
		while is_instance_valid(w) and not w.dead and t < 400:
			await tree.process_frame
			t += 1
		check(not is_instance_valid(w) or w.dead, "%s falls to your fire (hp %s, state %s, trigger %s)" % [kind,
			w.hp if is_instance_valid(w) else 0.0, w._state if is_instance_valid(w) else "", s.pilot.trigger])
	s.queue_free()


## A pack goes for you: you shoot back at whatever bites you without a click
## (and, fighting one, go on to the next that's after you).
func test_you_fire_back_at_a_pack() -> void:
	var s: Node = await _surface("thalassa")
	s.set_process(true)
	var pack: Array = []
	for k in 3:
		var w := SurfaceCreature.make("wolf")
		w.surface = s
		w.position = s._nearest_walkable(s.pilot.position + Vector2(220, -60 + k * 60))
		w.home = w.position
		s.objects.add_child(w)
		s.creatures.append(w)
		pack.append(w)
	s.pilot.hp = s.pilot.max_hp
	var t := 0
	while pack.any(func(w): return is_instance_valid(w) and not w.dead) and t < 900:
		await tree.process_frame
		s.pilot.hp = maxf(s.pilot.hp, 50.0)   # (not knocked out: this is about firing back)
		t += 1
	check(pack.all(func(w): return not is_instance_valid(w) or w.dead), "the pack falls without a click (%d frames)" % t)
	# Clicking one of a pack: after it falls you go on to the next one after you.
	var a := SurfaceCreature.make("boar")
	var b := SurfaceCreature.make("boar")
	for w in [a, b]:
		w.surface = s
		w.position = s._nearest_walkable(s.pilot.position + Vector2(200, 0))
		w.home = w.position
		s.objects.add_child(w)
		s.creatures.append(w)
		w._hunt(s.pilot)
	s.attack(a)
	t = 0
	while not a.dead and t < 400:
		await tree.process_frame
		s.pilot.hp = maxf(s.pilot.hp, 50.0)
		t += 1
	await tree.process_frame
	await tree.process_frame
	check(a.dead and s._attack_target == b, "on to the next attacker")
	s.queue_free()


## Every animal can be shot, and leaves Cybernetic Matter; big grazers fight
## back; hungry predators hunt other animals; the planet is twice as full.
func test_hunting_and_the_food_chain() -> void:
	var s: Node = await _surface("thalassa")
	await s.stream_all()   # (the whole planet in: it streams, a chunk at a time)
	s.set_process(true)
	var groups := 0
	for row in SurfaceCreature.FAUNA["fo"]:
		groups += row[1]
	check(s._fauna_plans.size() >= groups * SurfaceCreature.DENSITY, "twice the groups (%d animals)" % s._fauna_plans.size())
	# A sheep: under the cursor, attacked, falls, leaves matter you pick up.
	var sheep := SurfaceCreature.make("sheep")
	sheep.surface = s
	sheep.position = s._nearest_walkable(s.pilot.position + Vector2(250, 0))
	sheep.home = sheep.position
	s.objects.add_child(sheep)
	s.creatures.append(sheep)
	await tree.process_frame
	var at: Vector2 = sheep.position - Vector2(0, s.lift_at(sheep.position) + 20)
	check(s._hostile_at(at) == sheep, "a sheep can be clicked to attack")
	var before := int(Inventory.carried(s.state["player"]).get("cyber_matter", 0))
	s.attack(sheep)
	var t := 0
	while not sheep.dead and t < 400:
		await tree.process_frame
		t += 1
	check(sheep.dead, "the sheep falls")
	var drop = s.loot.back() if not s.loot.is_empty() else null
	check(drop != null and drop.contents[0][0] == "cyber_matter", "it leaves Cybernetic Matter")
	if drop:
		s.pilot.position = drop.position
		s._collect_loot()
		check(int(Inventory.carried(s.state["player"]).get("cyber_matter", 0)) > before, "and you take it (you carry it)")
	check(Items.ITEMS.has("cyber_matter"), "Cybernetic Matter is an item")
	# A goat shot at turns on you; a sheep would run.
	var goat := SurfaceCreature.make("goat")
	goat.surface = s
	goat.position = s._nearest_walkable(s.pilot.position + Vector2(200, 0))
	s.objects.add_child(goat)
	await tree.process_frame
	goat.attacked_by(s.pilot)
	check(goat._state == "chase" and goat._threat == s.pilot, "the goat fights back (%s)" % goat._state)
	goat.queue_free()
	# A hungry wolf hunts a hare and brings it down; the hare runs.
	s.pilot.position = s._nearest_walkable(s.pilot.position + Vector2(0, 900))   # (out of the way)
	var spot: Vector2 = s._nearest_walkable(s.pilot.position + Vector2(0, -900))
	var wolf := SurfaceCreature.make("wolf")
	var deer := SurfaceCreature.make("sheep")
	for c in [wolf, deer]:
		c.surface = s
		c.position = s._nearest_walkable(spot + (Vector2(-120, 0) if c == wolf else Vector2(60, 0)))
		c.home = c.position
		s.objects.add_child(c)
		s.creatures.append(c)
	await tree.process_frame
	wolf._hunger = 0.0
	wolf._look = 0.0
	t = 0
	var ran := false
	while not deer.dead and t < 1800:
		await tree.process_frame
		ran = ran or deer._state == "flee"
		t += 1
	check(ran, "the hunted sheep runs")
	check(deer.dead, "the wolf brings it down (%d frames; wolf %s %s, %.0f px, sheep hp %.0f %s)" % [t, wolf._state, wolf._threat, wolf.position.distance_to(deer.position), deer.hp, deer._state])
	s.queue_free()


## Tab opens the Field Computer (its tabs work, the bestiary lists what you've
## met), M the map; the toolbar heals with medicine and overcharges the rifle.
func test_field_computer_and_toolbar() -> void:
	var s: Node = await _surface("krystallos")
	s.set_process(true)
	var tab := InputEventKey.new()
	tab.keycode = KEY_TAB
	tab.pressed = true
	s._input(tab)
	check(s.field_menu.visible and not s.surface_map.visible, "Tab opens the Field Computer")
	for i in 4:
		s.field_menu.show_tab(i)
		await tree.process_frame
	s.field_menu.show_tab(s.field_menu.MAP_TAB)
	await tree.process_frame
	var page = s.field_menu._pages[s.field_menu.MAP_TAB]
	check(s.field_menu.visible and page.visible and page is SurfaceMap and page._view != null and not s.surface_map.visible,
		"the planet map is a tab of the Field Computer")
	s.field_menu.close()
	var m := InputEventKey.new()
	m.keycode = KEY_M
	m.pressed = true
	s._input(m)
	check(s.field_menu.visible and s.field_menu.current == s.field_menu.MAP_TAB, "M opens it on the map")
	s.field_menu.close()
	# The bestiary: a creature near you is met.
	var c := SurfaceCreature.make("icestag", "ic")
	c.surface = s
	c.position = s._nearest_walkable(s.pilot.position + Vector2(200, 0))
	s.objects.add_child(c)
	s.creatures.append(c)
	s._stream_fauna()
	check(s.state["player"]["bestiary"]["icestag"].get("seen", false), "a creature you come near is in the bestiary")
	s.field_menu.open(2)
	await tree.process_frame
	check(s.field_menu.visible, "the bestiary shows")
	s.field_menu.close()
	# Toolbar (9 slots; a new pilot's: rifle, medicine, energy cell): medicine
	# heals, an energy cell overcharges - from what you carry.
	check_eq(s.foot_toolbar().size(), 9, "nine toolbar slots")
	var items: Dictionary = s.carried()
	items["medicine"] = 2
	items["energy_cell"] = 1
	s.pilot.hp = 30.0
	var key := InputEventKey.new()
	key.keycode = KEY_2
	key.pressed = true
	s._input(key)
	check(s.pilot.hp == 80.0 and int(s.carried()["medicine"]) == 1, "2: medicine heals 50 (%.0f)" % s.pilot.hp)
	var every: float = s.pilot.fire_every()
	key.keycode = KEY_3
	s._input(key)
	check(s.overcharge_left() > 0.0 and s.pilot.fire_every() < every, "3: an energy cell overcharges the rifle")
	check(int(s.carried().get("energy_cell", 0)) == 0, "it uses the cell")
	# Your own toolbar: an empty slot does nothing; one you fill works.
	s.foot_toolbar()[6] = "medicine"
	items["medicine"] = 1
	s.pilot.hp = 30.0
	s._tool_cd.clear()
	key.keycode = KEY_7
	s._input(key)
	check(s.pilot.hp == 80.0, "7: medicine, once you put it there")
	key.keycode = KEY_9
	s._input(key)
	check(s.pilot.hp == 80.0, "9: an empty slot does nothing")
	check(s.toolbar != null and s.toolbar.is_inside_tree(), "the toolbar is on screen")
	s.queue_free()


## Stamina (Stamina): the green ring outside the shield's runs down as you go,
## faster in a fight; food and energy drinks bring it back; empty, you walk
## slower and don't heal; it's kept with the player.
func test_stamina() -> void:
	var s: Node = await _surface("krystallos")
	var p = s.pilot
	check(s.gauge._fuel_ring != null and s.gauge.fuel_name == "Stamina", "the gauge has a stamina ring")
	p.stamina = 50.0
	p._since_hit = 99.0
	p.trigger = null
	p._aiming = 0.0
	p._process(2.0)
	var calm: float = 50.0 - p.stamina
	p.stamina = 50.0
	p._since_hit = 0.0
	p._process(2.0)
	var fight: float = 50.0 - p.stamina
	check(calm > 0.0 and is_equal_approx(fight, calm * Stamina.COMBAT), "it runs down, %dx faster in a fight (%.2f / %.2f)" % [int(Stamina.COMBAT), calm, fight])
	# Food and energy drinks, from what you carry.
	var items: Dictionary = s.carried()
	items["figs"] = 1
	items["energy_drink"] = 1
	p.stamina = 10.0
	s._tool_cd.clear()
	s.use_item("figs")
	check(is_equal_approx(p.stamina, 10.0 + Stamina.FOOD) and int(items.get("figs", 0)) == 0, "food gives back %d (%.0f)" % [int(Stamina.FOOD), p.stamina])
	s.use_item("energy_drink")
	check(is_equal_approx(p.stamina, 10.0 + Stamina.FOOD + Stamina.DRINK), "an energy drink gives back %d (%.0f)" % [int(Stamina.DRINK), p.stamina])
	check(Inventory.toolbar_id("figs", true) == "figs" and Inventory.toolbar_id("energy_drink", true) == "energy_drink" and Inventory.toolbar_id("iron_ore", true) == "",
		"food and drinks go on the foot toolbar, ore doesn't")
	# Tired: slower, no healing.
	p.stamina = 0.0
	check(is_equal_approx(p.walk_speed(), p.speed * Stamina.TIRED_SPEED), "tired, you walk slower")
	p.hp = 50.0
	p._since_hit = 99.0
	p._process(1.0)
	check(p.hp == 50.0, "tired, you don't heal")
	# Kept with the player.
	p.stamina = 42.0
	s._update_tools(0.0)
	check(is_equal_approx(Stamina.of(s.state["player"]), 42.0), "kept with the player")
	var pd: Node = load("res://scripts/player_data.gd").new()
	pd.load_save_data(s.state["player"])
	check(is_equal_approx(pd.stamina, 42.0) and is_equal_approx(float(pd.get_save_data()["stamina"]), 42.0), "saved and loaded")
	pd.free()
	s.queue_free()


## Tiled ground: a ledge whose ground drops away behind it has its back edge
## drawn (a rim piece), so steps you'd otherwise not see show.
func test_ledges_show_their_back_edges() -> void:
	Ground3D.enabled = false      # (the 2D ground: its tile layers and pictures - the fallback)
	var s: Node = await _surface("krystallos")
	var rims := 0
	var want := 0
	var N: int = s.N
	for i in range(1, N):
		for j in range(1, N):
			var k: int = i * N + j
			if s._walk_t[s._terrain[k]] == 0 or s._rampd[k] != 0:
				continue
			if int(s._lvl[k - N]) < int(s._lvl[k]) and s._walk_t[s._terrain[k - N]] == 1 and s._rampd[k - N] == 0:
				want += 1
	check(want > 50, "Ida has ledges rising away from you (%d)" % want)
	var ids := []
	for r in s.TTILES.RIMS:
		ids.append(s._tile_pieces.find(s.TTILES.pc("ic", r)))
	check(not ids.has(-1), "the rim pieces are in the tile set")
	for layer in s.tile_ground.get_children():
		if layer is TileMapLayer:
			for id in ids:
				rims += layer.get_used_cells_by_id(id).size()
	check(rims > want / 2, "their back edges are drawn (%d rims for %d)" % [rims, want])
	check(s.TTILES.piece_texture("ic_rim_l") != null, "a rim piece is made")
	s.queue_free()


## A group of one kind defends itself: hurt one and the rest near it go for
## you too (even sheep); a lone hare still runs.
func test_groups_fight_together() -> void:
	var s: Node = await _surface("thalassa")
	for c in s.creatures:
		c.queue_free()
	s.creatures.clear()
	s._fauna_plans.clear()
	await tree.process_frame
	var herd: Array = []
	for k in 4:
		var c := SurfaceCreature.make("sheep")
		c.surface = s
		c.position = s._nearest_walkable(s.pilot.position + Vector2(260 + k * 30, -40 + k * 25))
		c.home = c.position
		s.objects.add_child(c)
		s.creatures.append(c)
		herd.append(c)
	await tree.process_frame
	herd[0].attacked_by(s.pilot)
	check(herd.all(func(c): return c._state == "chase" and c._threat == s.pilot), "the whole herd turns on you")
	var hp0: float = s.pilot.hp + s.pilot.shield   # (health and shield: a hit takes the shield first)
	for k in 240:
		for c in herd:
			c._process(1.0 / 60.0)
	check(s.pilot.hp + s.pilot.shield < hp0, "and they bite (%.0f -> %.0f)" % [hp0, s.pilot.hp + s.pilot.shield])
	var hare := SurfaceCreature.make("hare")
	hare.surface = s
	hare.position = s._nearest_walkable(s.pilot.position + Vector2(-300, 0))
	s.objects.add_child(hare)
	await tree.process_frame
	hare.attacked_by(s.pilot)
	check(hare._state == "flee", "a lone hare runs (%s)" % hare._state)
	s.queue_free()


## Animals don't get stuck in corners: one set down in a building's inside
## corner wanders off, one chasing you from behind a wall comes round it.
func test_creatures_get_out_of_corners() -> void:
	var s: Node = await _surface("thalassa")
	for c in s.creatures:
		c.queue_free()
	s.creatures.clear()
	s._fauna_plans.clear()
	await tree.process_frame
	var b = s.buildings[0]
	# A walkable spot hard against the building, outside it.
	var corner := Vector2.INF
	var r: Rect2 = b.bounds.grow(14)
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var q: Vector2 = s._nearest_walkable(p)
		if s.walkable_at(q) and not b.bounds.has_point(q):
			corner = q
			break
	check(corner != Vector2.INF, "found a spot by a building")
	var goat := SurfaceCreature.make("goat")
	goat.surface = s
	goat.position = corner
	goat.home = corner
	s.objects.add_child(goat)
	s.creatures.append(goat)
	await tree.process_frame
	var moved := 0.0
	var last: Vector2 = goat.position
	var stuck_frames := 0
	var walk_frames := 0
	for k in 2400:   # (40 s: it idles and grazes between strolls)
		goat._process(1.0 / 60.0)
		var d: float = goat.position.distance_to(last)
		if goat._state == "walk":
			walk_frames += 1
			if d < 0.05:
				stuck_frames += 1
		moved += d
		last = goat.position
	check(moved > 120.0, "it gets about (%.0f px)" % moved)
	check(stuck_frames < maxi(60, walk_frames / 5), "never pressed into a wall for long (%d of %d walking frames)" % [stuck_frames, walk_frames])
	# A wolf behind the building comes round it to you.
	var far_side: Vector2 = s._nearest_walkable(b.bounds.get_center() + (b.bounds.get_center() - s.pilot.position).normalized() * (b.bounds.size.length() * 0.5 + 60.0))
	var wolf := SurfaceCreature.make("wolf")
	wolf.surface = s
	wolf.position = far_side
	wolf.home = far_side
	s.objects.add_child(wolf)
	s.creatures.append(wolf)
	s.pilot.position = s._nearest_walkable(b.bounds.get_center() - (b.bounds.get_center() - far_side).normalized() * (b.bounds.size.length() * 0.5 + 60.0))
	await tree.process_frame
	wolf._hunt(s.pilot)
	var d0: float = wolf.position.distance_to(s.pilot.position)
	for k in 900:
		wolf._process(1.0 / 60.0)
		s.pilot.hp = s.pilot.max_hp
		if wolf.position.distance_to(s.pilot.position) < 60.0:
			break
	check(wolf.position.distance_to(s.pilot.position) < 80.0, "the wolf finds its way round (%.0f -> %.0f px)" % [d0, wolf.position.distance_to(s.pilot.position)])
	s.queue_free()


## walkable_at looks buildings up in a grid (and, inside one, only the walls
## and furniture near the point): the same answers as testing every wall of
## every building, in and around them.
func test_walkable_index_matches_the_full_check() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for pid in ["thalassa", "selene"]:
		var s: Node = await _surface(pid)
		var n := 0
		var bad := 0
		var bad_snap := 0
		var idx: Dictionary = s._snapshot_index(s.buildings)
		for b in s.buildings:
			for k in 300:
				var p: Vector2 = b.bounds.position + Vector2(rng.randf(), rng.randf()) * b.bounds.size
				p += Vector2(rng.randf_range(-40, 40), rng.randf_range(-40, 40))
				for clear in [5.0, 6.0, 8.0, 10.0]:
					n += 1
					var full: bool = s._walkable_in(p, clear, s.buildings)
					if s.walkable_at(p, clear) != full:
						bad += 1
					if s._walkable_snap(p, clear, idx) != full:
						bad_snap += 1
		check(n > 1000, "%s: %d points checked" % [pid, n])
		check_eq(bad, 0, "%s: the indexed check agrees everywhere" % pid)
		check_eq(bad_snap, 0, "%s: so does the worker threads' (the path grid's)" % pid)
		s.queue_free()
		await tree.process_frame
