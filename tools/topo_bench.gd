extends SceneTree
## The topology baseline: every ECurves solid of a model scored against the topology rules
## (scripts/editor/mesh/topo_score.gd) - its mesh as it is, and laid out again by edge_net.grid_any (timed).
##   XDG_DATA_HOME=<scratch> godot --headless --path . -s tools/topo_bench.gd -- <model.glb> <out.json> [name filter]
## Writes a JSON report (each solid + totals) and prints a table. Solids: the glb's nodes whose glTF extras
## carry "atrapos_curves" (the solid's recipe) of kind "edges".

const KEYS := ["quad_ratio", "pole_ratio", "angle_dev", "aspect", "sliver_ratio", "area_cv", "shade_ratio", "score"]


func _initialize() -> void:
	if OS.get_environment("FR_TRACE") != "":
		(load("res://scripts/editor/mesh/field_remesh.gd") as GDScript).set("trace", true)
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <model.glb> <out.json> [name filter]")
		quit(2)
		return
	var filt := args[2] if args.size() > 2 else ""
	if filt == "-":
		filt = ""
	# (tuning: -- <glb> <json> <filter or -> name=value ... : edge_net's switches)
	for a in args.slice(3):
		var kv := (a as String).split("=")
		if kv.size() == 2:
			var nn: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
			if kv[0].begins_with("FR."):   # (field_remesh's tuning)
				nn = load("res://scripts/editor/mesh/field_remesh.gd")
				kv[0] = kv[0].substr(3)
			nn.set(kv[0], str_to_var(kv[1]))
	var io: GDScript = load("res://scripts/editor/mesh/mesh_io.gd")
	var net: GDScript = load("res://scripts/editor/mesh/edge_net.gd")
	var ts: GDScript = load("res://scripts/editor/mesh/topo_score.gd")
	var root: Node3D = io.read(args[0])
	if root == null:
		printerr("can't read ", args[0])
		quit(2)
		return
	var solids := []
	_find(root, solids)
	var rows := []
	var tot := {"cur": _zero(), "grid": _zero()}
	var fails := 0
	var grid_ms := 0.0
	var methods := {}
	var qual := {}   # (each layout: [quads, slivers] over the model)
	var ring_bad := []   # (rings with slivers: [slivers, quads, solid, the face, why another way failed])   # (how the faces were laid out: "cc 3", "grid 4", "rings 0", ... - counts)
	var whys := {}
	var n := 0
	for s: Array in solids:
		var name: String = s[0]
		var rec: Dictionary = s[1]
		if str(rec.get("kind", "")) != "edges" or not rec.has("mesh"):
			continue
		if filt != "" and not name.contains(filt):
			continue
		var v := PackedVector3Array()
		var fl: Array = rec["mesh"]["v"]
		for i in range(0, fl.size() - 2, 3):
			v.append(Vector3(float(fl[i]), float(fl[i + 1]), float(fl[i + 2])))
		var t := PackedInt32Array()
		for x in rec["mesh"]["t"]:
			t.append(int(x))
		var fv := []
		for e in rec.get("fv", []):
			fv.append([int(e[0]), int(e[1]), float(e[2])])
		var chains := []
		for c in rec.get("chains", []):
			chains.append({"id": int(c.get("id", -1)), "closed": bool(c.get("closed", false))})
		var t0 := Time.get_ticks_usec()
		var cur: Dictionary = ts.score(v, t, fv, chains)
		var score_ms := (Time.get_ticks_usec() - t0) / 1000.0
		var area := 0.0
		for i in range(0, t.size(), 3):
			area += 0.5 * (v[t[i + 1]] - v[t[i]]).cross(v[t[i + 2]] - v[t[i]]).length()
		var L := clampf(sqrt(area / 380.0), 0.003, 1.0) * 0.55
		t0 = Time.get_ticks_usec()
		printerr("  laying out ", name, " (", t.size() / 3, " triangles)")
		var g: Dictionary = net.grid_any(v, t, fv, chains, L)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		grid_ms += ms
		var gl: Array = net.get("grid_log")
		for i in gl.size():
			var e: Array = gl[i]
			# (a rings fallback's quads: measured after it - the next face's note is its own)
			if str(e[1]) == "rings":
				pass
			if e.size() > 6 and not str(e[1]).ends_with("failed"):
				var mk := str(e[1]) + " " + str(e[2])
				if not qual.has(mk):
					qual[mk] = [0, 0, 0]
				qual[mk][0] += int(e[6][0])
				qual[mk][1] += int(e[6][1])
				qual[mk][2] += int(e[6][2]) if (e[6] as Array).size() > 2 else 0
		for i in gl.size():
			if str(gl[i][1]) == "rings made" and i > 0 and int(gl[i][6][1]) > 0:
				ring_bad.append([int(gl[i][6][1]), int(gl[i][6][0]), name, str(gl[i - 1][2]), str(gl[i - 1][3]).left(60)])
		for e in net.get("grid_log"):
			var key := "%s %s" % [str(e[1]), str(e[2])]
			methods[key] = int(methods.get(key, 0)) + 1
			if str(e[1]).ends_with("failed"):
				var why := str(e[3]).get_slice(":", 0) + ":" + str(e[3]).get_slice(":", 1).left(24)
				whys[why] = int(whys.get(why, 0)) + 1
		n += 1
		var row := {"name": name, "triangles": t.size() / 3, "chains": chains.size(), "area": area, "L": L,
			"score_ms": score_ms, "grid_ms": ms, "current": cur}
		_add(tot["cur"], cur)
		if g.is_empty():
			fails += 1
			row["grid"] = null
			row["grid_why"] = str(net.get("grid_why"))
		else:
			var gv := PackedVector3Array(g["v"])
			var gt := PackedInt32Array(g["t"])
			var gs: Dictionary = ts.score(gv, gt, g["fv"], chains)
			gs["kept"] = int(g.get("kept", 0))
			gs["cuts"] = int(g.get("cuts", 0))
			row["grid"] = gs
			_add(tot["grid"], gs)
		rows.append(row)
		print("%-28s %6d tris  cur %5.1f  grid %s  %7.0f ms" % [name.left(28), t.size() / 3, cur["score"],
			("%5.1f" % row["grid"]["score"]) if row["grid"] != null else "FAIL ", ms])
	var report := {"model": args[0], "solids": rows.size(), "grid_failures": fails, "grid_ms_total": grid_ms,
		"grid_ms_mean": grid_ms / maxf(1, n), "totals": {"current": _fin(tot["cur"]), "grid": _fin(tot["grid"])}, "rows": rows}
	var f := FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "\t"))
	f.close()
	print("")
	print("%-12s %8s %8s %8s %8s %8s %8s %10s %8s" % ["", "solids", "quads%", "poles", "slivers", "shade!", "open", "nonmanif", "score"])
	for k in ["current", "grid"]:
		var a: Dictionary = report["totals"][k]
		print("%-12s %8d %8.1f %8d %8d %8d %8d %10d %8.1f" % [k, a["n"], 100.0 * a["quad_ratio"], a["poles"], a["slivers"],
			a["shade_bad"], a["open_sides"], a["nonmanifold"], a["score_mean"]])
	print("grid_any: %d failed, %.0f ms total, %.0f ms a solid" % [fails, grid_ms, grid_ms / maxf(1, n)])
	print("layouts: ", methods)
	print("quality by layout [quads, slivers]: ", qual)
	ring_bad.sort_custom(func(x, y): return int(x[0]) > int(y[0]))
	for r in ring_bad.slice(0, 16):
		print("  ring ", r)
	print("why another way failed: ", whys)
	print("pairs refused: ", net.get("pair_why"))
	print("kept because: ", net.get("kept_why"))
	print("fills: ", net.get("fill_log"))
	print("prof: ", net.get("prof"))
	if filt != "":
		for e in net.get("grid_log"):
			print("  ", e)
	root.free()
	quit(0)


func _find(n: Node, out: Array) -> void:
	var rec = null
	if n.has_meta("curve_solid"):
		rec = n.get_meta("curve_solid")
	elif n.has_meta("extras"):
		var ex = n.get_meta("extras")
		if ex is Dictionary and ex.get("atrapos_curves") is Dictionary:
			rec = ex["atrapos_curves"]
	if rec is Dictionary:
		out.append([str(n.name), rec])
	for c in n.get_children():
		_find(c, out)


func _zero() -> Dictionary:
	return {"n": 0, "faces": 0, "quads": 0, "tris": 0, "interior": 0, "poles": 0, "slivers": 0, "inner_sides": 0,
		"shade_bad": 0, "open_sides": 0, "nonmanifold": 0, "misoriented": 0, "score_sum": 0.0, "angle_sum": 0.0, "cv_sum": 0.0}


func _add(a: Dictionary, r: Dictionary) -> void:
	a["n"] += 1
	for k in ["faces", "quads", "tris", "interior", "poles", "slivers", "inner_sides", "shade_bad", "open_sides", "nonmanifold", "misoriented"]:
		a[k] += int(r[k])
	a["score_sum"] += float(r["score"])
	a["angle_sum"] += float(r["angle_dev"])
	a["cv_sum"] += float(r["area_cv"])


func _fin(a: Dictionary) -> Dictionary:
	var o := a.duplicate()
	var n := maxf(1, a["n"])
	o["quad_ratio"] = float(a["quads"]) / maxf(1, a["faces"])
	o["pole_ratio"] = float(a["poles"]) / maxf(1, a["interior"])
	o["sliver_ratio"] = float(a["slivers"]) / maxf(1, a["quads"])
	o["shade_ratio"] = float(a["shade_bad"]) / maxf(1, a["inner_sides"])
	o["score_mean"] = a["score_sum"] / n
	o["angle_dev_mean"] = a["angle_sum"] / n
	o["area_cv_mean"] = a["cv_sum"] / n
	return o
