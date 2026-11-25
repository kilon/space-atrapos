extends SceneTree
## The frame-rate tour: plays every area and way of playing in a real window
## (vsync off, no frame cap) and measures each for a few seconds - title
## screen; space at home and in every empire (idle, flying, a battle, the
## Minotaur, every signal site, the Ship Computer's tabs, docked at a
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
var SurfaceCreatureS: GDScript
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
	PlanetsS = load("res://scripts/planet_data.gd")
	SignalSitesS = load("res://scripts/signal_sites.gd")
	SurfaceCreatureS = load("res://scripts/surface_creature.gd")
	SkillsS = load("res://scripts/skills.gd")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	Engine.max_fps = 0
	for i in 3:
		await process_frame
	var art: Node = root.get_node_or_null("ProcArt")
	while art and not art.ready_done:
		await process_frame
	# As the loading screen does: the main scenes loaded up front, kept.
	for path in ["res://main_menu.tscn", "res://main.tscn", "res://scenes/planet_surface.tscn", "res://scenes/station_menu.tscn"]:
		art.scenes[path] = load(path)
	galaxy.new_game(false)
	print("FPS tour: target %d FPS, %s, %s" % [TARGET, DisplayServer.window_get_size(), RenderingServer.get_video_adapter_name()])
	await _title()
	await _space_home()
	await _space_empires()
	await _signal_sites()
	await _landing()
	for pid in ["thalassa", "krystallos", "akrotiri", "kronos", "selene"]:
		await _surface(pid)
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
	load("res://scripts/cosmos/cosmos.gd").arrive_from = ""
	await _set_scene(load("res://scenes/cosmos.tscn").instantiate())
	while not _scene.build_settled():
		await process_frame
	var c: Node = _scene
	c.ship.control = false
	await _measure("3d space: by the station")
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
	c.get_out()
	c.walker.drive = {"move": Vector2(0.3, 1.0)}
	for i in 120:
		await process_frame
	await _measure("3d space: on foot among plants and animals")
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
		if x.kind == "pirate":
			c.target = x
			x.global_position = c.ship.global_position - c.ship.global_basis.z * 500.0 + Vector3(randf_range(-100, 100), randf_range(-100, 100), 0)
	c.ship.drive = {"fire": true, "throttle": 0.4}
	for i in 60:
		await process_frame
	await _measure("3d space: a dogfight with raiders")
	c.ship.drive = {}
	# Docked: walking the hangar.
	for x in c.npc_ships:
		x.queue_free()
	c.npc_ships.clear()
	c._pirate_cd = 9999.0
	c._place_ship()
	c.dry_run = true
	c.ship.hull = 200.0
	c.ship.shield = 120.0
	c.request_dock()
	while not (c.docked and c._dock.is_empty()):
		await process_frame
	c.get_out()
	c.walker.drive = {"move": Vector2(0.2, 1.0)}
	for i in 60:
		await process_frame
	await _measure("3d space: in a station's hangar")
	await _set_scene(null)


# --- Title -----------------------------------------------------------------

func _title() -> void:
	if not _wanted("title"):
		return
	await _set_scene(load("res://main_menu.tscn").instantiate())
	await _measure("title screen")


# --- Talos -----------------------------------------------------------------

## Talos, the editor: each page and tool, the Library's rooms, Versions with
## its infographic animating, and going from tool to tool on the rail.
func _talos() -> void:
	if not _wanted("talos"):
		return
	var host: Node = load("res://editor.tscn").instantiate()
	await _set_scene(host)
	for i in 10:
		await process_frame
	for id in ["dialogue", "chapters", "lore", "citizens", "sprites"]:
		host.show_tool(id)
		await _measure("talos: %s" % id)
	host.show_tool("scenarios")
	await _measure("talos: scenarios")
	host.show_tool("svg")
	await _measure("talos: svg editor")
	host.show_tool("patcher")
	var versions: Node = host.tools["patcher"]
	_drive = func():   # (the infographic's step animation, again and again)
		if Engine.get_process_frames() % 120 == 0:
			versions._view.restart()
	await _measure("talos: versions, infographic animating")
	_drive = Callable()
	host.show_tool("library")
	var zoo: Node = host.tools["library"]
	await _measure("talos: library, asset browser")
	for r in zoo.ROOMS.size():
		zoo.show_room(r)
		for i in 20:
			await process_frame
		await _measure("talos: library room %s" % str(zoo.ROOMS[r]).to_lower())
	zoo.show_browser()
	# Every tool built by now: going round the rail, a tool every 10 frames.
	var order := ["patcher", "dialogue", "scenarios", "library", "svg", "lore", "sprites", "chapters", "citizens"]
	var k := [0]
	_drive = func():
		if Engine.get_process_frames() % 10 == 0:
			host.show_tool(order[k[0] % order.size()])
			k[0] += 1
	await _measure("talos: switching tools on the rail")
	_drive = Callable()


# --- Space -----------------------------------------------------------------

func _enter_space(system: String) -> Node:
	galaxy.current_system = system
	save.travelling = system != galaxy.HOME
	save.landed_planet = ""
	await _set_scene(load("res://main.tscn").instantiate())
	for i in 40:
		await process_frame
	save.travelling = false
	_scene.ship.invulnerable = true   # (a battle shouldn't end the run)
	return _scene


func _space_home() -> void:
	if not _wanted("space"):
		return
	var main: Node = await _enter_space(galaxy.HOME)
	await _measure("space: home system, idle")
	# Flying: a new course across the system every 1.5 s.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t := [0.0]
	_drive = func():
		if Time.get_ticks_msec() / 1500.0 > t[0]:
			t[0] = Time.get_ticks_msec() / 1500.0 + 1.0
			main._move_ship(main.ship.global_position + Vector2.from_angle(rng.randf() * TAU) * 3000.0)
	await _measure("space: flying across the system")
	# A charted system's nav beacon on screen: its ring, its waves and their nebula trails.
	_drive = Callable()
	var nav: Node2D = get_first_node_in_group("nav_beacons")
	if nav:
		galaxy.charted[galaxy.current_system] = true
		main.ship.global_position = nav.global_position + Vector2(-500, 250)
		main.ship.stop()
		main._zoom = 0.6   # (zoomed out: the trails cover the most screen)
		await _measure("space: nav beacon, charted (nebula trails)")
		galaxy.charted.erase(galaxy.current_system)
		main._zoom = 1.0
	# A battle: 6 pirates on you, you fighting back (a new one for each that falls).
	main.ship.stop()
	var foes: Array = []
	_drive = func():
		for e in foes.duplicate():   # (in place: a lambda's own reassignments don't last)
			if not is_instance_valid(e) or not e.is_alive():
				foes.erase(e)
		while foes.size() < 6:
			var e: Node2D = main.spawn_enemy(main.ship.global_position + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(500, 900))
			foes.append(e)
		if not main.ship._target_valid():
			main.ship.set_attack_target(foes[0], true)
		main.ship.hull = main.ship.max_hull
	await _measure("space: battle, 6 pirates")
	for e in foes:
		if is_instance_valid(e):
			e.queue_free()
	_drive = Callable()
	# The Minotaur.
	var m: Node2D = main.spawn_ship(main.ship.global_position + Vector2(0, -900), "minotaur")
	main.ship.set_attack_target(m, true)
	await _measure("space: the Minotaur boss")
	if is_instance_valid(m):
		m.queue_free()
	main.ship.set_attack_target(null)
	# A siege: an invasion fleet of 10 shooting a burning station (flames,
	# bolts on the station), you nearby.
	galaxy._set_relation("sparta", galaxy.owner_of(galaxy.current_system), -90.0)
	var besieged: Node2D = main.get_tree().get_nodes_in_group("stations")[1]
	galaxy.damage_station(besieged.station_id, 70.0)
	var fl: Dictionary = root.get_node("Fleets")._new_fleet("sparta", "invade", galaxy.current_system, 10, [])
	fl["target"] = galaxy.current_system
	main.ship.stop()
	main.ship.global_position = besieged.global_position + Vector2(-600, 400)
	await _measure("space: a siege, a burning station")
	for n in main.neutrals.get_children():
		if n.get("fleet_id") == fl["id"]:
			n.queue_free()
	root.get_node("Fleets").fleets.erase(fl["id"])
	galaxy.repair_station(besieged.station_id, 100.0)
	# The Ship Computer: the map (flying on), then every tab.
	main._open_panel(main.ship_menu, main.ship_menu.MAP_TAB)
	await _measure("space: Ship Computer, system map")
	for i in main.ship_menu.TABS.size():
		if i == main.ship_menu.MAP_TAB:
			continue
		main.ship_menu.show_tab(i)
		await _measure("space: Ship Computer, %s" % main.ship_menu.TABS[i].to_lower(), 2.0)
	# The probe scanner: the map with probes out and an analysis's dozens of signatures on it.
	if _wanted("space: Ship Computer, probe scanner"):
		main.player_data.add_equipment("probe_scanner")
		main.ship_menu.show_tab(main.ship_menu.MAP_TAB)
		var mp = main.ship_menu.page(main.ship_menu.MAP_TAB)
		mp.show_probes(true)
		main.probes.launch_pattern(main.ship.global_position, 8000.0)
		for p in main.probes.probes:
			p["at"] = p["pos"]
		main.probes._resolve()
		mp._view.fit()
		await _measure("space: Ship Computer, probe scanner", 2.0)
		mp.show_probes(false)
		# The automaton on the operating table: its anatomy, incisions open, each layer in turn.
	if _wanted("space: Ship Computer, surgery"):
		main.ship_menu.show_tab(main.ship_menu.REPAIR_TAB)
		var bay = main.ship_menu._pages[main.ship_menu.REPAIR_TAB]
		var rs := RandomNumberGenerator.new()
		rs.seed = 5
		for spec in [["crack", 0], ["drift", 1], ["burn", 2], ["leak", 3], ["crack", 4]]:
			Parts.add_fault(main.player_data.condition, "automaton", "arms", spec[0], spec[1], rs)
		bay._pick_body("automaton")
		bay.pick_part("arms")
		for f in bay.faults():
			f["found"] = true
		var t1 := Time.get_ticks_msec()
		while not load("res://scripts/anatomy_art.gd").ready() and Time.get_ticks_msec() - t1 < 8000:
			await process_frame
		for i in [2, 3, 4]:
			var cut: Dictionary = bay._surgery.cut_of(i)
			cut["done"].fill(true)
			cut["open"] = true
		bay._fill()
		var layers := ["muscles", "veins", "nerves", "skeleton"]
		var k2 := [0, 0.0]
		_drive = func():
			if Time.get_ticks_msec() / 500.0 > k2[1]:
				k2[1] = Time.get_ticks_msec() / 500.0 + 1.0
				k2[0] += 1
				bay.set_layer(layers[k2[0] % 4])
				bay._surgery._mouse = bay._surgery.size * 0.5 + Vector2(120, 0).rotated(k2[0])
		await _measure("space: Ship Computer, surgery (the automaton's anatomy)", 3.0)
		_drive = Callable()
		Parts.clear_all(main.player_data.condition, "automaton")
		bay._pick_body("ship")
	main.ship_menu.close()
	# Mining by hand: a prospected rock's vein cut in its band (the autopilot), the readout up.
	if _wanted("space: mining by hand"):
		var rock: Node2D = null
		for r in get_nodes_in_group("asteroids"):
			if r.kind != "ice" and (rock == null or r.global_position.distance_to(main.ship.global_position) < rock.global_position.distance_to(main.ship.global_position)):
				rock = r
		if rock:
			main.ship.global_position = rock.global_position + Vector2(0, 300)
			main.ship.rotation = 0.0
			main.ship.stop()
			rock.scanned = true
			main.ship.set_attack_target(rock)
			main.ship.mining_auto = true
			await _measure("space: mining by hand", 2.0)
			main.ship.mining_auto = false
			main.ship.set_attack_target(null)
	# Near death: the failing screen, the cracks, the sparks off the hull.
	if _wanted("space: near death"):
		var hull: float = main.ship.hull
		main.ship.hull = main.ship.max_hull * 0.06
		Parts.by_health(main.player_data.condition, "ship", 0.06)
		main.ship.apply_tech()
		await _measure("space: near death (failing screen, sparks)", 2.0)
		Parts.clear_all(main.player_data.condition, "ship")
		main.ship.hull = hull
		main.ship.apply_tech()
	# Docked: every station tab.
	var st: Node2D = get_nodes_in_group("stations")[0]
	main.dock(st)
	var t0 := Time.get_ticks_msec()
	while not main.station_menu.visible and Time.get_ticks_msec() - t0 < 6000:
		await process_frame
	for i in main.station_menu.TABS.size():
		main.station_menu.show_tab(i)
		await _measure("space: station, %s" % main.station_menu.TABS[i].to_lower(), 2.0)
	main.station_menu.close()


## One system of each other empire: its ships and stations, flying through.
func _space_empires() -> void:
	if not _wanted("space"):
		return
	var seen := {galaxy.owner_of(galaxy.HOME): true}
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for sys in galaxy.SYSTEMS:
		var owner: String = galaxy.owner_of(sys)
		if seen.has(owner):
			continue
		seen[owner] = true
		var main: Node = await _enter_space(sys)
		var t := [0.0]
		_drive = func():
			if Time.get_ticks_msec() / 1500.0 > t[0]:
				t[0] = Time.get_ticks_msec() / 1500.0 + 1.0
				main._move_ship(main.ship.global_position + Vector2.from_angle(rng.randf() * TAU) * 3000.0)
		await _measure("space: %s (%s), flying" % [sys, owner if owner != "" else "unclaimed"])
	# A Spartan station's missions board: nine painted (non-Minoan) portraits,
	# each moving - baked into pictures (Portrait), or they cost ~5 ms apiece.
	var ssys := ""
	for sys in galaxy.SYSTEMS:
		if ssys == "" and galaxy.owner_of(sys) == "sparta":
			ssys = sys
	var smain: Node = await _enter_space(ssys)
	_drive = Callable()
	var sst: Node2D = null
	for s in get_nodes_in_group("stations"):
		if s.station_id != "" and s.empire == "sparta":
			sst = s
	if sst:
		smain.dock(sst)
		var t1 := Time.get_ticks_msec()
		while not smain.station_menu.visible and Time.get_ticks_msec() - t1 < 6000:
			await process_frame
		smain.station_menu.show_tab(smain.station_menu.TABS.find("MISSIONS"))
		for i in 30:
			await process_frame   # (the portraits bake)
		await _measure("space: sparta station, missions (painted portraits)", 2.0)
		smain.station_menu.close()
	# The system with the most planets and moons (up to 12 planets, gas giants
	# with up to three moons): flying among them.
	var biggest := ""
	for sys in galaxy.systems:
		if biggest == "" or galaxy.systems[sys]["planets"].size() > galaxy.systems[biggest]["planets"].size():
			biggest = sys
	var bmain: Node = await _enter_space(biggest)
	var bodies: Array = get_nodes_in_group("planet_bodies")
	var k := [0, 0.0]
	_drive = func():
		if Time.get_ticks_msec() / 1500.0 > k[1]:
			k[1] = Time.get_ticks_msec() / 1500.0 + 1.0
			var b: Node2D = bodies[k[0] % bodies.size()]
			k[0] += 1
			if is_instance_valid(b):
				bmain._move_ship(b.global_position + Vector2.from_angle(rng.randf() * TAU) * (b.radius + 400.0))
	await _measure("space: biggest system (%d planets and moons), flying" % galaxy.systems[biggest]["planets"].size())
	galaxy.current_system = galaxy.HOME


func _signal_sites() -> void:
	if not _wanted("site"):
		return
	for kind in SignalSitesS.KINDS:
		var main: Node = await _enter_space(galaxy.HOME)
		var sig := {"id": "fps:%s" % kind, "kind": kind, "pos": [5000.0, 0.0], "located": true, "done": false, "seed": 12345}
		sig["level"] = "hard"
		var b: Node2D = load("res://scripts/signal_beacon.gd").new()
		b.sig = sig
		main.add_child(b)
		main.enter_site(b)
		var foes := []
		_drive = func():   # (fight whatever is there)
			main.ship.hull = main.ship.max_hull
			if not main.ship._target_valid():
				for e in get_nodes_in_group("enemies"):
					if e.is_alive() and e.global_position.distance_to(main.ship.global_position) < 2500.0:
						main.ship.set_attack_target(e, true)
						break
		await _measure("signal site: %s" % kind)


# --- Landing ---------------------------------------------------------------

## The landing animation, the surface building in the background meanwhile.
func _landing() -> void:
	if not _wanted("landing"):
		return
	var main: Node = await _enter_space(galaxy.HOME)
	var body: Node2D = main._planet_body("thalassa")
	main.ship.global_position = body.global_position + Vector2(body.radius + 300, 0)
	for i in 20:
		await process_frame
	main.land_on("thalassa")
	print("@@profile landing")
	# The landing animation (the surface building meanwhile, in the
	# background) - until the ship has shrunk away and the screen fades.
	var frames := []
	var last := Time.get_ticks_usec()
	var t0 := Time.get_ticks_msec()
	while main.ship.sprite.visible and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	_record_long("landing on thalassa (animation, the surface building)", frames)
	# Then the switch to the surface, under the black fade (its first frame
	# draws the whole ground: a moment of black, not a stutter you see).
	frames = []
	last = Time.get_ticks_usec()
	while (current_scene == main or current_scene == null or not current_scene.has_method("show_world")) and Time.get_ticks_msec() - t0 < 30000:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	for i in 3:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	print("@@profile -")
	frames.sort()
	print("  info landing: the fade to the surface (black screen)      longest frame %.0f ms" % frames[-1])
	_scene = current_scene
	save.travelling = false


## _record, and the frames over HITCH_MS listed.
func _record_long(name: String, frames: Array) -> void:
	var long := []
	for i in frames.size():
		if frames[i] > HITCH_MS:
			long.append("%d: %.0f ms" % [i, frames[i]])
	_record(name, frames)
	if not long.is_empty():
		print("       long frames (of %d): %s" % [frames.size(), ", ".join(long)])


# --- Planet surfaces -------------------------------------------------------

const FIGHTERS := {"fo": "wolf", "ic": "frostwolf", "vo": "pyrohound"}


func _surface(pid: String) -> void:
	if not _wanted(pid) and not _wanted("surface"):
		return
	save.landed_planet = pid
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	await _set_scene(s)
	while not s.is_built:
		await process_frame
	for i in 30:
		await process_frame
	var label := "%s (%s)" % [pid, PlanetsS.PLANETS[pid].get("tiles", "?")]
	var pilot: Node2D = s.pilot
	var keep_alive := func(): pilot.hp = pilot.max_hp
	_drive = keep_alive
	await _measure("surface %s: idle at the ship" % label)
	# A long walk: on and on in one direction, the world streaming in.
	var dir := [Vector2.RIGHT]
	var home: Vector2 = pilot.position
	_drive = func():
		pilot.hp = pilot.max_hp
		if not pilot.moving:
			dir[0] = dir[0].rotated(0.6)
			s._walk_to(s._nearest_walkable(pilot.position + dir[0] * 700.0))
	await _measure("surface %s: walking (streaming)" % label, 6.0)
	# A fight: a pack on you, you firing back.
	var kind: String = FIGHTERS.get(PlanetsS.PLANETS[pid].get("tiles", ""), "")
	if kind != "":
		var pack: Array = []
		var set_id: String = PlanetsS.PLANETS[pid]["tiles"]
		_drive = func():
			pilot.hp = pilot.max_hp
			for w in pack.duplicate():
				if not is_instance_valid(w) or w.dead:
					pack.erase(w)
			while pack.size() < 5:
				var w: Node2D = SurfaceCreatureS.make(kind, set_id)
				w.surface = s
				w.position = s._nearest_walkable(pilot.position + Vector2.from_angle(randf() * TAU) * 260.0)
				w.home = w.position
				s.objects.add_child(w)
				s.creatures.append(w)
				w._hunt(pilot)
				pack.append(w)
		await _measure("surface %s: fight, a pack of 5 %s" % [label, kind])
		_drive = keep_alive
		for w in pack:   # (the fight over: the pack gone, not biting through the next scenarios)
			if is_instance_valid(w):
				s.creatures.erase(w)
				w.queue_free()
	# A brawl with skills: pirates fighting hand to hand, every blow and spell of yours (Skills).
	var st: Dictionary = SkillsS.state(s.state["player"])
	var ranks_were: Dictionary = st["ranks"].duplicate()
	for id in SkillsS.SKILLS:
		st["ranks"][id] = 5
	var gang: Array = []
	var cast := ["pygmachia", "phlox", "sweep", "lance", "leap", "keraunos", "pankration", "aegis", "comet", "eidola", "laktisma", "guard"]
	var next := [0.0, 0]
	_drive = func():
		pilot.hp = pilot.max_hp
		pilot.stamina = 100.0
		for g in gang.duplicate():
			if not is_instance_valid(g) or g.dead:
				gang.erase(g)
		while gang.size() < 4:
			var where: Vector2 = s._nearest_walkable(pilot.position + Vector2.from_angle(randf() * TAU) * randf_range(120.0, 260.0))
			var g: Node2D = s._spawn_npc(where, gang.size() + randi() % 9, where, "pirate")
			g.max_hp = 600.0
			g.hp = 600.0
			gang.append(g)
		if Time.get_ticks_msec() / 1000.0 >= next[0] and pilot.busy <= 0.0:
			next[0] = Time.get_ticks_msec() / 1000.0 + 0.45
			s._tool_cd.clear()
			var id: String = cast[next[1] % cast.size()]
			next[1] += 1
			s.use_skill(id, gang[next[1] % gang.size()].position)
	await _measure("surface %s: a brawl with skills (4 pirates, every blow and spell)" % label, 7.0)
	_drive = keep_alive
	s.stop_attack()
	for g in gang:
		if is_instance_valid(g):
			s.npcs.erase(g)
			g.queue_free()
	for e in s.npcs.duplicate():
		if e.species == "eidolon":
			e.vanish()
	st["ranks"] = ranks_were
	pilot.style = "rifle"
	pilot.position = home
	# Inside a building.
	var inside := Vector2.INF
	for b in s.buildings:
		var c: Vector2 = s._nearest_walkable(b.bounds.get_center())
		if b.bounds.has_point(c):
			inside = c
			break
	if inside != Vector2.INF:
		pilot.position = inside
		pilot.moving = false
		await _measure("surface %s: inside a building" % label)
		pilot.position = home
	# The Field Computer: inventory, then the map.
	s.field_menu.open(s.field_menu.INVENTORY_TAB)
	await _measure("surface %s: Field Computer, inventory" % label, 2.0)
	s.field_menu.show_tab(s.field_menu.MAP_TAB)
	await _measure("surface %s: Field Computer, map" % label, 2.0)
	s.field_menu.show_tab(s.field_menu.SKILLS_TAB)
	await _measure("surface %s: Field Computer, the Spell Book" % label, 2.0)
	s.field_menu.close()
	# At the ship: the transfer screen.
	s.board_ship()
	await _measure("surface %s: cargo transfer at the ship" % label, 2.0)
	for c in s.get_children():
		if c.get_script() == load("res://scripts/transfer_panel.gd"):
			c.close()


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
	# A new game from the title screen, as a player starts one.
	var menu: Node = load("res://main_menu.tscn").instantiate()
	await _set_scene(menu)
	var t_title := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_title < 2000:   # (a player takes a moment at the title - by time, not frames: 60 frames are a tenth of a second here)
		await process_frame
	galaxy.new_game(false)
	var old_id := menu.get_instance_id()   # (ids, not the nodes: they're freed by the change)
	await _watch("loading: new game from the title", func(): menu._on_start(),
		func(): return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.name == "Main" and not save.travelling and current_scene.build_settled())
	_scene = current_scene
	var main: Node = _scene
	main.ship.invulnerable = true
	for i in 30:
		await process_frame
	await _watch("loading: Ship Computer, first open", func(): main._open_panel(main.ship_menu, main.ship_menu.INVENTORY_TAB), func(): return true)
	var tab := [0]
	await _watch("loading: Ship Computer, every tab", func(): pass, func():
		if Engine.get_process_frames() % 8 == 0:
			tab[0] += 1
			if tab[0] < main.ship_menu.TABS.size():
				main.ship_menu.show_tab(tab[0])
		return tab[0] >= main.ship_menu.TABS.size())
	main.ship_menu.close()
	for i in 40:
		await process_frame
	await _watch("loading: the Archive window (F1)", func(): EditorDocs.open(main, "space", EditorDocs.GAME), func(): return true)
	for w in get_nodes_in_group("archive_window"):
		w.close()
	await _watch("loading: Talos over the game", func(): save.open_talos(), func(): return true)
	for i in 30:
		await process_frame
	await _watch("loading: back from Talos", func(): save.close_talos(), func(): return true)
	# Docking and undocking (the ship next to a station).
	var st: Node2D = get_nodes_in_group("stations")[0]
	main.ship.global_position = st.global_position + Vector2(260, 0)
	for i in 20:
		await process_frame
	await _watch("loading: docking at a station", func(): main.dock(st), func(): return main.station_menu.visible, 20.0)
	await _watch("loading: undocking", func(): main.station_menu.close(), func(): return not main._ship_animating, 20.0)
	# A signal site: in and out.
	# A jump to the next system.
	var dest: String = galaxy.neighbors(galaxy.current_system)[0]
	old_id = main.get_instance_id()
	main.player_data.fuel = 100.0
	await _watch("loading: a jump to the next system", func(): main.jump_to(dest),
		func(): return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.name == "Main" and not save.travelling, 30.0)
	_scene = current_scene
	main = _scene
	main.ship.invulnerable = true
	for i in 30:
		await process_frame
	# Landing on a planet and taking off again (home: Amnissos).
	galaxy.current_system = galaxy.HOME
	main = await _enter_space(galaxy.HOME)
	var body: Node2D = main._planet_body("thalassa")
	main.ship.global_position = body.global_position + Vector2(body.radius + 300, 0)
	for i in 20:
		await process_frame
	old_id = main.get_instance_id()
	await _watch("loading: landing on a planet", func(): main.land_on("thalassa"),
		func(): return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.has_method("show_world") and current_scene.get("is_built") == true, 40.0)
	_scene = current_scene
	var s: Node = _scene
	for i in 60:
		await process_frame
	old_id = s.get_instance_id()
	await _watch("loading: taking off", func(): s.take_off(),
		func(): return current_scene != null and current_scene.get_instance_id() != old_id and current_scene.name == "Main" and not save.travelling, 30.0)
	_scene = current_scene
	# The 3D preview from the title screen (Cosmos: a system in 3D built under the veil).
	var title: Node = load("res://main_menu.tscn").instantiate()
	await _set_scene(title)
	for i in 30:
		await process_frame
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
