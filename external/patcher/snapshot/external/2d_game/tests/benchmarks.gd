extends SceneTree
## Performance benchmarks. Compares with tests/benchmark_baseline.json and
## fails (exit 1) when something got more than 50% slower.
##
##   godot --headless --path . -s tests/benchmarks.gd                       run + compare
##   godot --headless --path . -s tests/benchmarks.gd -- --save-baseline    store as baseline
##
## Timings are machine-dependent: save a baseline on the machine you test on.

const BASELINE := "res://tests/benchmark_baseline.json"
const SLOWER := 1.5

var results := {}


func _initialize() -> void:
	_run()


func _bench(name: String, ms: float, unit := "ms") -> void:
	results[name] = ms
	print("  %-38s %9.3f %s" % [name, ms, unit])


func _run() -> void:
	await process_frame
	await process_frame
	var galaxy: Node = root.get_node("Galaxy")
	var save: Node = root.get_node("SaveGame")
	var proc: Node = root.get_node("ProcArt")
	# As in the game: the loading screen's bake (incl. building textures) first.
	var t_load := Time.get_ticks_usec()
	while not proc.ready_done:
		await process_frame
	var load_ms := (Time.get_ticks_usec() - t_load) / 1000.0
	print("Benchmarks")
	_bench("startup sprite load", load_ms)
	# Sprites: loading every PNG fresh (bypassing the cache) and the Minoan tiles.
	var keys: Array = proc.bake_jobs()
	var t := Time.get_ticks_usec()
	for k in keys:
		ResourceLoader.load(k[1], "Texture2D", ResourceLoader.CACHE_MODE_IGNORE)
	_bench("sprite load (per sprite)", (Time.get_ticks_usec() - t) / 1000.0 / keys.size())
	MinoanTiles.forget()
	t = Time.get_ticks_usec()
	await MinoanTiles.precompose(self)
	_bench("Minoan tile assembly", (Time.get_ticks_usec() - t) / 1000.0)
	# Galaxy simulation.
	galaxy.new_game(false)
	var was: bool = galaxy.active
	galaxy.active = true
	t = Time.get_ticks_usec()
	for i in 2000:
		galaxy._process(0.5)
	_bench("galaxy simulation (per 0.5 s tick)", (Time.get_ticks_usec() - t) / 1000.0 / 2000.0)
	t = Time.get_ticks_usec()
	for i in 200:
		galaxy.find_route("klotho", "skylla")
	_bench("galaxy route search", (Time.get_ticks_usec() - t) / 1000.0 / 200.0)
	galaxy.active = was
	# Planet surfaces: build, path queries, a walking frame.
	var old: String = save.landed_planet
	for pid in ["thalassa", "selene", "krystallos"]:
		save.landed_planet = pid
		t = Time.get_ticks_usec()
		var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
		root.add_child(s)
		while not s.is_built:
			await process_frame
		_bench("surface build: " + pid, (Time.get_ticks_usec() - t) / 1000.0)
		await process_frame
		if pid == "thalassa":
			s.set_process(false)
			var rng := RandomNumberGenerator.new()
			rng.seed = 3
			var c: Vector2 = s.lander.position
			var pairs := []
			while pairs.size() < 300:
				var a := c + Vector2(rng.randf_range(-1800, 1800), rng.randf_range(-900, 900))
				var z := c + Vector2(rng.randf_range(-1800, 1800), rng.randf_range(-900, 900))
				if s.walkable_at(a) and s.walkable_at(z):
					pairs.append([a, z])
			t = Time.get_ticks_usec()
			for p in pairs:
				s.find_path(p[0], p[1])
			_bench("surface find_path (per query)", (Time.get_ticks_usec() - t) / 1000.0 / pairs.size())
			s.pilot.position = pairs[0][0]
			s._walk_to(pairs[0][1])
			t = Time.get_ticks_usec()
			for i in 300:
				s._process(1.0 / 60.0)
			_bench("surface frame update (walking)", (Time.get_ticks_usec() - t) / 1000.0 / 300.0)
		s.queue_free()
		await process_frame
	save.landed_planet = old
	# Space: the main scene's per-frame script time.
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 300:   # warm-up: art baked on first use, ships spawned
		await process_frame
	var frames := 0
	var acc := 0.0
	while frames < 240:
		await process_frame
		acc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		frames += 1
	_bench("space frame process time (warm)", acc / frames)
	main.queue_free()
	await process_frame
	_report()


func _report() -> void:
	if OS.get_cmdline_user_args().has("--save-baseline"):
		var f := FileAccess.open(BASELINE, FileAccess.WRITE)
		f.store_string(JSON.stringify(results, "\t"))
		f.close()
		print("\nSaved as the baseline (%s)." % BASELINE)
		quit(0)
		return
	if not FileAccess.file_exists(BASELINE):
		print("\nNo baseline yet: run with -- --save-baseline to store one.")
		quit(0)
		return
	var base: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASELINE))
	var slow := []
	print("\nCompared with the baseline:")
	for k in results:
		if not base.has(k):
			continue
		var ratio: float = results[k] / maxf(float(base[k]), 0.001)
		var flag := "  SLOWER" if ratio > SLOWER and results[k] - float(base[k]) > 0.05 else ""
		print("  %-38s %6.2fx%s" % [k, ratio, flag])
		if flag != "":
			slow.append(k)
	print("\n%s" % ("No regressions." if slow.is_empty() else "%d regressions: %s" % [slow.size(), ", ".join(slow)]))
	quit(0 if slow.is_empty() else 1)
