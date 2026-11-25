## Walks about for 20 s with every streaming step of PlanetSurface._process timed, and lists
## the frames over 25 ms:  python3 tools/live.py run -f external/live_scripts/perf_walk_spikes.gd
func run():
	# Walk far; each frame run the surface's _process by hand with every streaming step timed.
	var s = tree.current_scene
	s.set_process(false)
	var worst = {"chunks": 0, "plans": 0, "fauna": 0, "nav": 0, "rest": 0, "frame": 0, "other": 0}
	var sum = {"chunks": 0, "plans": 0, "fauna": 0, "nav": 0, "rest": 0, "frame": 0, "other": 0}
	var spikes = []
	s.path_calls = 0
	s.path_us = 0
	var goal = s._nearest_walkable(s.pilot.position + Vector2(2600, 1300))
	s._walk_to(goal)
	var t = 0.0
	var n = 0
	while t < 20.0:
		await tree.process_frame
		var dt = tree.root.get_process_delta_time()
		t += dt
		n += 1
		var t0 = Time.get_ticks_usec()
		s._stream_chunks(3000)
		var t1 = Time.get_ticks_usec()
		s._stream_plans()
		var t2 = Time.get_ticks_usec()
		s._stream_fauna()
		var t3 = Time.get_ticks_usec()
		s._stream_nav()
		var t4 = Time.get_ticks_usec()
		# the rest of _process: attack, tools, loot, health, walking, occlusion...
		s._update_attack(dt)
		s._update_tools(dt)
		s._collect_loot()
		s._update_health()
		var t5 = Time.get_ticks_usec()
		var parts = {"chunks": t1 - t0, "plans": t2 - t1, "fauna": t3 - t2, "nav": t4 - t3, "rest": t5 - t4, "frame": int(dt * 1e6)}
		parts["other"] = parts["frame"] - (t5 - t0)
		for k in parts:
			worst[k] = maxi(worst[k], parts[k])
			sum[k] += parts[k]
		if dt > 0.025:
			spikes.append([snappedf(dt * 1000.0, 0.1), "chunks %d plans %d fauna %d nav %d rest %d" % [parts["chunks"] / 1000, parts["plans"] / 1000, parts["fauna"] / 1000, parts["nav"] / 1000, parts["rest"] / 1000], "buildings %d chunks %d" % [s.buildings.size(), s._chunks.size()]])
		if not s.pilot.moving and s._far_goal == Vector2.INF:
			goal = s._nearest_walkable(s.pilot.position + Vector2(randf_range(-2000, 2000), randf_range(-1000, 1000)))
			s._walk_to(goal)
	s.set_process(true)
	var avg = {}
	for k in sum: avg[k] = snappedf(sum[k] / 1000.0 / n, 0.01)
	var w = {}
	for k in worst: w[k] = snappedf(worst[k] / 1000.0, 0.1)
	return {"frames": n, "avg_ms": avg, "worst_ms": w, "spikes": spikes, "path_calls": s.path_calls, "path_ms_total": snappedf(s.path_us / 1000.0, 0.1)}
