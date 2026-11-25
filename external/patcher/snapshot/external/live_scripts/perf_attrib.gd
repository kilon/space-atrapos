## Where a surface frame goes: the frame with the tiles, scenery, objects, creatures or HUD hidden
## in turn, and the GPU / render-CPU times:  python3 tools/live.py run -f external/live_scripts/perf_attrib.gd
func _measure(frames: int) -> float:
	var sum = 0.0
	for k in 10: await tree.process_frame
	for k in frames:
		await tree.process_frame
		sum += tree.root.get_process_delta_time()
	return snappedf(sum / frames * 1000.0, 0.01)

func run():
	var s = tree.current_scene
	var vp = tree.root
	RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var out = {}
	out["layers"] = []
	for l in s.get_node("TileGround").get_children():
		if l is TileMapLayer: out["layers"].append([l.y_sort_enabled, l.get_used_cells().size()])
	out["all_ms"] = await _measure(90)
	out["gpu_ms"] = snappedf(RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid()), 0.01)
	out["cpu_render_ms"] = snappedf(RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid()), 0.01)
	var tg = s.get_node("TileGround")
	tg.visible = false
	out["no_tiles_ms"] = await _measure(90)
	tg.visible = true
	var objs = s.objects
	objs.visible = false
	out["no_objects_ms"] = await _measure(90)
	objs.visible = true
	s._hud.visible = false
	out["no_hud_ms"] = await _measure(90)
	s._hud.visible = true
	# creatures hidden only (not freed)
	for c in s.creatures: c.visible = false
	out["no_creatures_drawn_ms"] = await _measure(90)
	for c in s.creatures: c.visible = true
	for c in s.creatures: c.set_process(false)
	out["no_creature_process_ms"] = await _measure(90)
	for c in s.creatures: c.set_process(true)
	# scenery props hidden
	for h in s._chunk_holders.values(): h.visible = false
	out["no_scenery_ms"] = await _measure(90)
	for h in s._chunk_holders.values(): h.visible = true
	var crt = tree.root.get_node_or_null("CrtFilter")
	out["crt_node"] = str(crt) + " " + (str(crt.visible) if crt else "")
	out["canvas_layers"] = []
	for n in tree.root.get_children():
		out["canvas_layers"].append(n.name + ":" + n.get_class())
	return out
