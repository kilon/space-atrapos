## Frame rate and render stats on a planet surface, over 180 frames:
##   python3 tools/live.py run -f external/live_scripts/perf_fps.gd
## (turn vsync off first for the real headroom: live.py run "DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)")
func run():
	var s = tree.current_scene
	var out = []
	var samples = []
	var worst = 0.0
	for k in 180:
		await tree.process_frame
		var dt = tree.root.get_process_delta_time()
		samples.append(dt)
		worst = maxf(worst, dt)
	samples.sort()
	var sum = 0.0
	for v in samples: sum += v
	return {"fps_avg": snappedf(samples.size() / sum, 0.1), "frame_ms_median": snappedf(samples[samples.size() / 2] * 1000.0, 0.1), "frame_ms_p95": snappedf(samples[int(samples.size() * 0.95)] * 1000.0, 0.1), "worst_ms": snappedf(worst * 1000.0, 0.1),
		"creatures": s.creatures.size(), "npcs": s.npcs.size(), "props": s._props.size() if "_props" in s else -1,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "objects_drawn": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"process_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.1), "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps}
