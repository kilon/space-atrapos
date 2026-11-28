extends SceneTree
## The frame-rate tour: plays every area and way of playing in a real window
## (vsync off, no frame cap) and measures each for a few seconds - title
## screen; space at home and in every empire (idle, flying, a battle, the
## Minotaur, every signal site, the Automaton's tabs, docked at a
## station); landing; every landable planet's surface (idle, a long walk that
## streams the world in, a fight, inside a building, the Field Computer, the
## transfer screen at the ship). A scenario passes when its average is at
## least TARGET FPS (600) and 95% of its frames are too (frame time <=
## 1000/TARGET ms), and none of its frames takes over FREEZE_MS (a stutter).
## tools/fps_test.py also compares each with tests/fps_baseline.json (slower
## by a quarter: flagged, even above the bar).
##
##   python3 tools/fps_test.py [filter]      (runs this in a window, your user data untouched)
##   godot --path . --resolution 1920x1080 -s tests/fps_tour.gd [-- <filter>]
##
## Not headless: rendering is what's measured. Not part of tools/test.py (the
## tests run headless, 12 Godots at once - no frame rate to speak of).

var TARGET := 600.0          # --target=N to judge against another frame rate (the game's bar: 600)
const SECONDS := 4.0          # measured per scenario
const WARMUP := 0.75          # s run first, not measured (art baked on first use)
const HITCH_MS := 25.0        # a frame this long counts as a hitch
const FREEZE_MS := 50.0       # any frame this long fails a scenario (a stutter you'd see)

var results: Array = []
var _filter := ""
var _shots := false           # --shots: a screenshot of each scenario (user://fps_shots/)
var _attrib := false          # --attrib: for a slow scenario, what its frame time goes on
var _scene: Node
var _drive := Callable()      # called every frame while measuring (keeps a scenario going)
var galaxy: Node              # (the autoloads: not known by name in a -s script)
var save: Node
var PlanetsS: GDScript           # (class names that use autoloads: loaded at run time)
var SignalSitesS: GDScript
var SkillsS: GDScript


func _initialize() -> void:
	_run()


func _run() -> void:
	var args: Array = Array(OS.get_cmdline_user_args())
	_attrib = args.has("--attrib")
	_shots = args.has("--shots")
	for a in args:
		if a.begins_with("--target="):
			TARGET = float(a.trim_prefix("--target="))
	args = args.filter(func(a): return not a.begins_with("--"))   # (--attrib, --mute, --window-at=...)
	_filter = args[0] if not args.is_empty() else ""
	galaxy = root.get_node("Galaxy")
	save = root.get_node("SaveGame")
	PlanetsS = load("res://scripts/sim/planet_data.gd")
	SignalSitesS = load("res://scripts/sim/signal_sites.gd")
	SkillsS = load("res://scripts/sim/skills.gd")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	Engine.max_fps = 0
	for i in 3:
		await process_frame
	var art: Node = root.get_node_or_null("ProcArt")
	while art and not art.ready_done:
		await process_frame
	# As the loading screen does: the main scenes loaded up front, kept.
	for path in ["res://scenes/ui/main_menu.tscn", "res://scenes/world/cosmos.tscn", "res://scenes/ui/station_menu.tscn"]:
		art.scenes[path] = load(path)
	galaxy.new_game(false)
	print("FPS tour: target %d FPS, %s, %s" % [TARGET, DisplayServer.window_get_size(), RenderingServer.get_video_adapter_name()])
	await _title()
	await _space3d()
	await _talos()
	await _loading()
	_set_scene(null)
	_report()


## A section runs if the filter names it ("space", "surface", "thalassa") or
## one of its scenarios ("space: battle" - its scenario names begin with it).
func _wanted(section: String) -> bool:
	return _filter == "" or section.contains(_filter) or _filter.contains(section)


## Measures `name` for SECONDS (after WARMUP), calling _drive every frame.
func _measure(name: String, seconds := SECONDS) -> void:
	if _filter != "" and not name.contains(_filter):
		return
	var t_end := Time.get_ticks_usec() + int(WARMUP * 1e6)
	while Time.get_ticks_usec() < t_end:
		await process_frame
		if _drive.is_valid():
			_drive.call()
	print("@@profile " + name)   # (for tools/fps_test.py --profile)
	var frames: Array = []
	var cost := {"script": 0.0, "physics": 0.0, "render_cpu": 0.0, "gpu": 0.0}
	var vp := root.get_viewport_rid()
	var last := Time.get_ticks_usec()
	t_end = last + int(seconds * 1e6)
	while last < t_end:
		await process_frame
		if _drive.is_valid():
			_drive.call()
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
		cost["script"] += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		cost["physics"] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		cost["render_cpu"] += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		cost["gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
	print("@@profile -")
	if _shots:
		DirAccess.make_dir_recursive_absolute("user://fps_shots")
		root.get_texture().get_image().save_png("user://fps_shots/%s.png" % name.validate_filename().replace(" ", "_"))
	for k in cost:
		cost[k] /= maxf(1.0, frames.size())
	_record(name, frames, cost)
	if _attrib and not results[-1]["ok"]:
		await _attribute()


## The average frame (ms) over `n` frames.
func _avg_frame(n := 40) -> float:
	for i in 5:
		await process_frame
		if _drive.is_valid():
			_drive.call()
	var t0 := Time.get_ticks_usec()
	for i in n:
		await process_frame
		if _drive.is_valid():
			_drive.call()
	return (Time.get_ticks_usec() - t0) / 1000.0 / n


## What each script costs: its nodes' own processing switched off for a
## moment (not their children's) - the frame time saved, against the frames
## just before and after (a battle changes as it goes).
func _attribute() -> void:
	# First: everything's processing off (what's left: drawing and the engine).
	var procs := []
	for n in root.find_children("*", "", true, false):
		if n.is_processing() and n.get_script() != null:
			procs.append(n)
	var on_ms := await _avg_frame(60)
	procs = procs.filter(func(n): return is_instance_valid(n))
	for n in procs:
		n.set_process(false)
	var off_ms := await _avg_frame(60)
	for n in procs:
		if is_instance_valid(n):
			n.set_process(true)
	print("       frame %.2f ms; with no script processing %.2f ms (%d nodes)" % [on_ms, off_ms, procs.size()])
	var by_script := {}
	for n in root.find_children("*", "", true, false):
		var sc: Script = n.get_script()
		if sc == null or not (n.is_processing() or n.is_physics_processing()):
			continue
		var key: String = sc.resource_path.get_file()
		if key == "" or key.begins_with("fps_tour"):
			continue
		if not by_script.has(key):
			by_script[key] = []
		by_script[key].append(n)
	var rows := []
	for key in by_script:
		var before := await _avg_frame(30)
		var nodes: Array = by_script[key].filter(func(n): return is_instance_valid(n))
		var was := []
		for n in nodes:
			was.append([n.is_processing(), n.is_physics_processing()])
			n.set_process(false)
			n.set_physics_process(false)
		var off := await _avg_frame(30)
		for i in nodes.size():
			if is_instance_valid(nodes[i]):
				nodes[i].set_process(was[i][0])
				nodes[i].set_physics_process(was[i][1])
		var after := await _avg_frame(30)
		rows.append([(before + after) * 0.5 - off, key, nodes.size(), (before + after) * 0.5])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	print("       what its scripts' processing costs (per frame):")
	for r in rows.slice(0, 12):
		if r[0] > 0.3:
			print("         %-32s x%-4d %5.1f ms  (of %.1f)" % [r[1], r[2], r[0], r[3]])


func _record(name: String, frames: Array, cost := {}) -> void:
	var sorted := frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in frames:
		total += f
	var avg := frames.size() / (total / 1000.0)
	var p95: float = sorted[int(sorted.size() * 0.95)]
	var p99: float = sorted[int(sorted.size() * 0.99)]
	var worst: float = sorted[-1]
	var hitches := frames.filter(func(f): return f > HITCH_MS).size()
	var ok := avg >= TARGET and p95 <= 1000.0 / TARGET and worst <= FREEZE_MS
	var r := {"name": name, "fps": avg, "p95_ms": p95, "low1_fps": 1000.0 / p99, "worst_ms": worst, "hitches": hitches,
		"frames": frames.size(), "ok": ok,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "cost_ms": cost}
	results.append(r)
	print("  %-4s %-46s %6.0f fps  p95 %5.1f ms  1%%low %5.0f fps  worst %6.1f ms  hitches %d  (%d draw calls, %d nodes)" % [
		"ok" if ok else "SLOW", name, avg, p95, r["low1_fps"], worst, hitches, r["draw_calls"], r["objects"]])
	if not cost.is_empty():
		print("       (per frame: scripts %.1f ms, physics %.1f ms, render CPU %.1f ms, GPU %.1f ms)" % [cost["script"], cost["physics"], cost["render_cpu"], cost["gpu"]])


func _set_scene(n: Node) -> void:
	_drive = Callable()
	if paused:
		paused = false
	if is_instance_valid(_scene):
		_scene.queue_free()
		await process_frame
		await process_frame
	_scene = n
	if n:
		root.add_child(n)
		current_scene = n


# --- 3D space (Cosmos: the game turning 3D) ----------------------------------

## The home system in 3D: the view from out among the planets, low over an
## ocean world's sea and coast, over a volcanic world, and cruising between
## planets (the ground refining itself as it comes).
func _space3d() -> void:
	if not _wanted("3d"):
		return
	galaxy.current_system = galaxy.HOME
	load("res://scripts/world/space/cosmos.gd").arrive_from = ""
	await _set_scene(load("res://scenes/world/cosmos.tscn").instantiate())
	while not _scene.build_settled():
		await process_frame
	var c: Node = _scene
	c.ship.control = false
	await _measure("3d space: by the station")
	# The Automaton open on its 3D maps (the game going on behind).
	for tab in [[1, "3d space: the solar map open"], [2, "3d space: the galaxy map open"]]:
		c.open_computer(tab[0])
		for i in 90:
			await process_frame
		await _measure(tab[1])
	c._computer.close()
	for i in 60:
		await process_frame
	var ocean := -1
	var lava := -1
	for i in c.planets.size():
		match str(c.planets[i].rec.get("type", "")):
			"ocean":
				ocean = i if ocean < 0 else ocean
			"volcanic":
				lava = i if lava < 0 else lava
	c.warp_to(ocean, 800.0, 0.6)
	await _measure("3d space: over an ocean world")
	c.warp_to(ocean, 30.0, 0.7)
	c.ship.drive = {"throttle": 0.6}
	await _measure("3d space: low over the sea")
	c.warp_to(lava, 120.0, 0.9)
	c.ship.drive = {"throttle": 0.6}
	await _measure("3d space: over a volcanic world")
	# On foot: landed in the woods, walking among the plants and animals.
	c.warp_to(ocean, 40.0, 0.0, 0.0, c.land_up(ocean))
	c.land()
	for i in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	c.walker.drive = {"move": Vector2(0.3, 1.0)}
	for i in 120:
		await process_frame
	await _measure("3d space: on foot among plants and animals")
	await _under_the_sea(c, ocean)
	# A pirate camp's guards shooting it out with you.
	var camp: Vector3 = c.camps_of(c.planets[ocean])[0][0]
	var d := camp.normalized()
	var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var at := (camp + t * 30.0).normalized()
	var pl: Node3D = c.planets[ocean]
	c.walker.global_position = pl.global_position + at * (pl.radius + c.walker.floor_at(at * pl.radius) + 0.05)
	c.walker.hp = 100000.0
	c.walker.drive = {"fire": true}
	for i in 4:
		c._life()
	for i in 60:
		await process_frame
	await _measure("3d space: a fight at a pirate camp")
	# Walking through a town: the palace, the houses, the people.
	var ti := -1
	for k in c.planets.size():
		if not c.planets[k].towns.is_empty():
			ti = k
			break
	if ti >= 0:
		var tpl: Node3D = c.planets[ti]
		var txf: Transform3D = load("res://scripts/world/life/cosmos_town.gd").frame(tpl.towns[0], tpl.radius)
		c.walker.drive = {}
		c.walker.set_deck(null)
		c.walker.planet = tpl
		c.walker.global_position = tpl.global_position + txf * Vector3(0, 0.3, 40)
		c.walker.heading = (tpl.global_basis * txf.basis) * Vector3(0, 0, -1)
		c.walker.velocity = Vector3.ZERO
		for i in 300:
			c._towns_tick()
			await process_frame
			var tw = c._towns.get(tpl, [null])[0]
			if tw and tw.built and c.citizens.size() >= 5:
				break
		c.walker.drive = {"move": Vector2(0.0, 0.6)}
		for i in 60:
			await process_frame
		await _measure("3d space: walking through a town")
		# The Automaton's planet map (the globe, the town walked into marked), then its plan.
		c.walker.drive = {}
		c.open_computer(1)
		var pm: Node = c._computer.maps().sub(0)
		for i in 240:
			await process_frame
			if pm._view._globe.mesh is ArrayMesh:
				break
		for i in 30:
			await process_frame
		await _measure("3d space: the planet map open")
		pm.open_plan("town:0", true)
		for i in 90:
			await process_frame
		await _measure("3d space: a town's plan open")
		c._computer.close()
		for i in 30:
			await process_frame
		c.walker.planet = c.planets[ocean]
		c.walker.global_position = pl.global_position + at * (pl.radius + c.walker.floor_at(at * pl.radius) + 0.05)
	# Down a dungeon: its torchlit rooms, its dead coming for you.
	for k in c.planets.size():
		var dpl: Node3D = c.planets[k]
		var ds: Array = c.dungeons_of(dpl)
		if ds.is_empty():
			continue
		c.walker.drive = {}
		c.walker.set_deck(null)
		c.walker.planet = dpl
		var site: Dictionary = {}
		for e in ds:
			if e[0]["kind"] == "dungeon":
				site = e[0]
		if site.is_empty():
			continue
		var key: String = c._chest_key(dpl, site)
		for i in 300:   # (in its world's ground: built as you come near)
			c._dungeon_life(dpl, site["dungeon"]["mouth"])
			if c._dungeon_live.has(key) and c._dungeon_live[key]["woke"]:
				break
			await process_frame
		var dg = c._dungeon_live[key]["node"]
		var room: Rect2 = dg.rooms[0][0]
		c.walker.global_position = dg.to_global(Vector3(room.get_center().x, 0.05, room.get_center().y))
		c.walker.heading = dg.global_basis.x
		c.walker.hp = 100000.0
		c.walker.drive = {"move": Vector2(0.0, 0.7), "fire": true}
		for i in 60:
			await process_frame
		await _measure("3d space: in a dungeon")
		c.walker.drive = {}
		break
	c.walker.set_deck(null)
	c.walker.planet = c.planets[ocean]
	c.walker.global_position = pl.global_position + at * (pl.radius + c.walker.floor_at(at * pl.radius) + 0.05)
	c.walker.hp = 100.0
	c.board() if c.walker.global_position.distance_to(c.ship.global_position) < 11.0 else null
	if c.walker:
		c.walker.queue_free()
		c.walker = null
		c.cam.to_ship()
	c.warp_to(ocean, 45000.0, 0.6)
	c.ship.look_at(c.planets[ocean].global_position, Vector3.UP)
	c.cam._q = c.ship.global_basis.get_rotation_quaternion()
	c.ship.drive = {"throttle": 1.0}
	c.target = c.planets[ocean]
	c.ship.toggle_cruise()
	await _measure("3d space: the Hyperion drive down to a planet")
	# A dogfight: three raiders round you, everyone firing.
	c.ship.drive = {}
	c.ship.cruise = 0
	c.warp_to(ocean, 12000.0, 0.6)
	c._life_rng.seed = 5
	c._pirate_cd = 0.0
	c._traffic()
	c.ship.hull = 1e9
	c.ship.shield = 1e9
	for x in c.npc_ships:
		if is_instance_valid(x) and x.kind == "pirate":
			c.target = x
			x.global_position = c.ship.global_position - c.ship.global_basis.z * 500.0 + Vector3(randf_range(-100, 100), randf_range(-100, 100), 0)
	c.ship.drive = {"fire": true, "throttle": 0.4}
	for i in 60:
		await process_frame
	await _measure("3d space: a dogfight with raiders")
	c.ship.drive = {}
	# A space monster at its lair, attacking.
	if not c.lairs.is_empty():
		for x in c.npc_ships:
			if is_instance_valid(x):
				x.queue_free()
		c.npc_ships.clear()
		var lr: Node3D = c.lairs[0]
		c.ship.global_position = lr.global_position + Vector3(1600, 200, 0)
		c.ship.look_at(lr.global_position, Vector3.UP)
		c.cam._q = c.ship.global_basis.get_rotation_quaternion()
		c._lairs_tick()
		var mon = lr.monster
		for i in 120:
			await process_frame
			if mon and mon.built:
				break
		c.target = mon
		c.ship.drive = {"fire": true}
		for i in 90:
			await process_frame
		await _measure("3d space: a space monster's attack")
		c.ship.drive = {}
	# Docked: walking the hangar.
	for x in c.npc_ships:
		if is_instance_valid(x):
			x.queue_free()
	c.npc_ships.clear()
	c._pirate_cd = 9999.0
	c._place_ship()
	c.dry_run = true
	c.ship.hull = 200.0
	c.ship.shield = 120.0
	c.request_dock(true)
	while not (c.docked and c._dock.is_empty()):
		await process_frame
	c.disembark()
	c.walker.drive = {"move": Vector2(0.2, 1.0)}
	for i in 60:
		await process_frame
	await _measure("3d space: in a station's hangar")
	await _set_scene(null)


# --- Title -----------------------------------------------------------------

## Under the sea (CosmosUnderwater): the camera dived 5 m under the surface
## of a 10-15 m deep stretch of the ocean world, by day - the underwater
## passes, the floor's life, the fish. (The camera's put there by hand: its
## own keeps it over the water.)
func _under_the_sea(c: Node, ocean: int) -> void:
	var uw: Node = c.get("underwater")
	if uw == null:
		uw = load("res://scripts/world/life/cosmos_underwater.gd").new()
		uw.cosmos = c
		c.add_child(uw)
	var pl: Node3D = c.planets[ocean]
	var d := Vector3.ZERO
	for i in 20000:
		var v := Vector3(sin(i * 1.7 + 0.3), cos(i * 2.3), sin(i * 0.9 + 1.0)).normalized()
		var h: float = pl.shape.height(v)
		if h < -10.0 and h > -15.0 and v.dot(pl.sun_dir) > 0.55:
			d = v
			break
	if d == Vector3.ZERO:
		return
	var depth: float = -pl.shape.height(d)
	c.walker.global_position = pl.global_position + d * pl.radius   # (swimming at the surface above)
	c.walker.drive = {}
	c.cam.set_process(false)
	c.cam.set_physics_process(false)
	var eye: Vector3 = pl.global_position + d * (pl.radius - 5.0)
	var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	c.cam.global_position = eye
	c.cam.look_at(eye + t * 10.0 - d * (depth - 5.0) * 0.25, d)
	for i in 600:   # (the floor's cells built, their buffers in)
		await process_frame
		if i > 90 and not uw.shown_cells.is_empty() and uw._apply.is_empty() and uw._area_task == -1:
			break
	await _measure("3d space: under the sea")
	c.cam.set_process(true)
	c.cam.set_physics_process(true)


func _title() -> void:
	if not _wanted("title"):
		return
	await _set_scene(load("res://scenes/ui/main_menu.tscn").instantiate())
	await _measure("title screen")


# --- Talos -----------------------------------------------------------------

## Talos, the editor: each page and tool, Patch Notes with its infographic
## animating, and going from tool to tool on the rail.
func _talos() -> void:
	if not _wanted("talos"):
		return
	var host: Node = load("res://scenes/editor/editor.tscn").instantiate()
	await _set_scene(host)
	for i in 10:
		await process_frame
	for id in ["dialogue", "chapters", "lore", "citizens", "sprites"]:
		host.show_tool(id)
		await _measure("talos: %s" % id)
	host.show_tool("mesh")
	await _measure("talos: mesh editor")
	host.show_tool("anim")
	await _measure("talos: animation editor")
	host.show_tool("fx")
	await _measure("talos: effects editor")
	# Patch Notes (the title screen's now), its infographic animating.
	var versions: Control = load("res://scripts/editor/patcher.gd").open_over(host)
	for i in 5:
		await process_frame
	_drive = func():   # (the infographic's step animation, again and again)
		if Engine.get_process_frames() % 120 == 0:
			versions._view.restart()
	await _measure("talos: patch notes, infographic animating")
	_drive = Callable()
	versions._back()
	for i in 3:
		await process_frame
	# Every tool built by now: going round the rail, a tool every 10 frames.
	var order := ["mesh", "dialogue", "anim", "lore", "sprites", "chapters", "citizens"]
	var k := [0]
	_drive = func():
		if Engine.get_process_frames() % 10 == 0:
			host.show_tool(order[k[0] % order.size()])
			k[0] += 1
	await _measure("talos: switching tools on the rail")
	_drive = Callable()


# --- Space -----------------------------------------------------------------





# --- Landing ---------------------------------------------------------------



# --- Planet surfaces -------------------------------------------------------

const FIGHTERS := {"fo": "wolf", "ic": "frostwolf", "vo": "pyrohound"}



# --- Loading: every change of scene and every first opening -----------------

## A transition (`action`, then frames until `done` is true, and 20 more): its
## longest frame must stay under LOAD_MS - the game never freezes, whatever
## loads (a new game, a jump, landing, taking off, docking, Talos, the
## computers, the Archive). Judged on that alone (not the frame rate).
const LOAD_MS := 33.4
func _watch(name: String, action: Callable, done: Callable, timeout := 30.0) -> void:
	if _filter != "" and not name.contains(_filter) and not _filter.contains("loading"):
		return
	for i in 5:
		await process_frame
	print("@@profile " + name)   # (for tools/fps_test.py --profile)
	var frames := []
	var last := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	action.call()
	var after := -1
	var split := []   # per frame: [ms of scripts and processing (up to the drawing), ms of drawing (the renderer: first-time shaders, pictures)]
	var marks := [last, last]   # when the frame's drawing began and ended
	var pre := func(): marks[0] = Time.get_ticks_usec()
	var post := func(): marks[1] = Time.get_ticks_usec()
	RenderingServer.frame_pre_draw.connect(pre)
	RenderingServer.frame_post_draw.connect(post)
	while Time.get_ticks_msec() - t0 < timeout * 1000.0:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		split.append([(marks[0] - last) / 1000.0, (marks[1] - marks[0]) / 1000.0])
		last = now
		if after < 0 and done.call():
			after = 0
		if after >= 0:
			after += 1
			if after > 20:
				break
	RenderingServer.frame_pre_draw.disconnect(pre)
	RenderingServer.frame_post_draw.disconnect(post)
	print("@@profile -")
	var sorted := frames.duplicate()
	sorted.sort()
	var worst: float = sorted[-1] if not sorted.is_empty() else 0.0
	var long := []
	for i in frames.size():
		if frames[i] > 8.4:
			long.append("%d: %.0f (scripts %.0f, drawing %.0f)" % [i, frames[i], split[i][0], split[i][1]] if frames[i] > LOAD_MS else "%d: %.0f" % [i, frames[i]])
	var ok := worst <= LOAD_MS and after >= 0
	results.append({"name": name, "fps": frames.size() / maxf(0.001, (Time.get_ticks_msec() - t0) / 1000.0), "p95_ms": 0.0, "low1_fps": 0.0,
		"worst_ms": worst, "hitches": long.size(), "frames": frames.size(), "ok": ok, "load": true, "seconds": (Time.get_ticks_msec() - t0) / 1000.0})
	print("  %-4s %-46s %5.2f s   worst frame %6.1f ms   frames over 8 ms: %d%s" % ["ok" if ok else "SLOW", name, (Time.get_ticks_msec() - t0) / 1000.0, worst, long.size(),
		"" if after >= 0 else "  (never finished)"])
	if not long.is_empty():
		print("       long frames (ms): %s" % ", ".join(long.slice(0, 24)))


func _loading() -> void:
	if not _wanted("loading"):
		return
	var old_id := 0
	# The 3D preview from the title screen (Cosmos: a system in 3D built under the veil).
	var title: Node = load("res://scenes/ui/main_menu.tscn").instantiate()
	await _set_scene(title)
	for i in 30:
		await process_frame
	# (the title's warm-up done first - CosmosWarm, a second or so: New game is never pressed sooner)
	var w0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - w0 < 10000 and title.get_children().any(func(n): return n.get_script() != null and str(n.get_script().resource_path).ends_with("cosmos_warm.gd")):
		await process_frame
	print("  (the title's warm-up: %.1f s)" % ((Time.get_ticks_msec() - w0) / 1000.0))
	old_id = title.get_instance_id()
	await _watch("loading: 3D space from the title", func(): title._on_space3d(false),
		func(): return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.name == "Cosmos" and current_scene.build_settled(), 30.0)
	_scene = current_scene
	for i in 30:
		await process_frame
	old_id = _scene.get_instance_id()
	var dest3: String = _scene.gates[0].to
	await _watch("loading: a jump through a 3D gate", func(): _scene.jump(dest3),
		func(): return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.name == "Cosmos" and current_scene.build_settled(), 30.0)
	_scene = current_scene


# --- Report ----------------------------------------------------------------

func _report() -> void:
	var slow := results.filter(func(r): return not r["ok"])
	for t in [240.0, 600.0]:   # (both bars, whatever the target)
		var under := results.filter(func(r): return not r.get("load", false) and (r["fps"] < t or r["p95_ms"] > 1000.0 / t))
		print("At %d FPS (average, and 95%% of frames): %d of %d scenarios fall short%s" % [t, under.size(), results.size(),
			"" if under.is_empty() else " - " + ", ".join(under.map(func(r): return "%s %.0f" % [r["name"], r["fps"]]))])
	print("\n%d scenarios, %d under %d FPS%s" % [results.size(), slow.size(), TARGET, ":" if not slow.is_empty() else "."])
	for r in slow:
		if r.get("load", false):
			print("  - %s: a frame of %.0f ms (loading must stay under %.0f ms)" % [r["name"], r["worst_ms"], LOAD_MS])
		else:
			print("  - %s: %.0f fps (p95 %.1f ms, worst %.1f ms)" % [r["name"], r["fps"], r["p95_ms"], r["worst_ms"]])
	var f := FileAccess.open("user://fps_tour.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
	quit(0 if slow.is_empty() else 1)
