extends SceneTree
## Screenshots for the guide, the tutorial and the encyclopedia (data/docs/
## shots.json): each shot sets up a moment of the game and saves the screen,
## full size, as a PNG - tools/doc_shots.py then draws its infographic over it
## and saves it into data/docs/shots/. Run by that tool, in a window:
##   godot --path . -s tests/doc_shots.gd -- [shot ids...] --out=DIR
## (no ids: every shot).

const ALL := ["space3d", "space3d_ground", "space3d_foot", "space3d_town", "space3d_people", "space3d_inside", "space3d_dungeon", "space3d_cave", "space3d_fight", "space3d_monster", "space3d_mining", "space3d_dig", "space3d_digging", "space3d_building", "space3d_vein", "space3d_underwater", "space3d_pad", "space3d_hangar", "space3d_port", "space3d_trader", "map3d", "galaxy3d", "planet3d", "town_plan3d", "space3d_start"]

var galaxy: Node
var save: Node
var _scene: Node
var _want: Array = []
var _out := "user://doc_shots"
var _done: Array = []


func _initialize() -> void:
	_run()


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif not a.begins_with("--"):
			_want.append(a)
	if _want.is_empty():
		_want = ALL.duplicate()
	DirAccess.make_dir_recursive_absolute(_out)
	galaxy = root.get_node("Galaxy")
	save = root.get_node("SaveGame")
	root.get_node("Settings").fps_counter = false   # (a development run shows it: not in the guide's pictures)
	# 60 frames a second, paced by the engine and not by the screen (a locked or
	# sleeping screen holds a v-synced window at one frame a second: the shots took an hour).
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60
	for i in 3:
		await process_frame
	var art: Node = root.get_node_or_null("ProcArt")
	while art and not art.ready_done:
		await process_frame
	galaxy.new_game(false)
	if _any(["space3d", "space3d_ground", "space3d_foot", "space3d_town", "space3d_people", "space3d_inside", "space3d_dungeon", "space3d_cave", "space3d_fight", "space3d_monster", "space3d_mining", "space3d_dig", "space3d_digging", "space3d_building", "space3d_vein", "space3d_underwater", "space3d_pad", "space3d_hangar", "space3d_port", "space3d_trader"]):
		await _space3d()
	if _any(["space3d_mining"]):
		await _mining3d()
	if _any(["space3d_start"]):
		await _start3d()
	if _any(["map3d", "galaxy3d"]):
		await _maps3d()
	if _any(["planet3d", "town_plan3d"]):
		await _planet_map3d()
	await _set_scene(null)
	print("DOC SHOTS: " + ",".join(_done))
	quit()


## The Automaton's 3D maps in Knossos: the solar map (the system swept,
## a world picked, a course set to a station), then the galaxy map (a few
## systems visited, one picked, a route plotted to it).
func _maps3d() -> void:
	galaxy.new_game(false)
	galaxy.current_system = galaxy.HOME
	for id in ["klotho", "lachesis", "delos", "kyros", "nyx", "hekate", "erebos", "naxos", "g1_sitia", "g8_kissamos", "tartaros", "pylos", "thera"]:
		galaxy.been[id] = true
	galaxy.reveal(Vector2.ZERO, 10500.0)
	galaxy.reveal(Vector2(-6000, 6000), 5000.0)
	load("res://scripts/world/space/cosmos.gd").arrive_from = ""
	await _set_scene(load("res://scenes/world/cosmos.tscn").instantiate())
	var c: Node = _scene
	while not c.build_settled():
		await process_frame
	c.ship.control = false
	c.target = c.stations[1] if c.stations.size() > 1 else null
	c.open_computer(1)
	for i in 30:
		await process_frame
	c._computer.maps().show_sub(1)
	var mp: Node = c._computer.maps().sub(1)
	var v: Node = mp._view
	v.rebuild()
	var pk := ""
	for k in v.objs:
		if v.objs[k]["kind"] == "planet" and str(v.objs[k]["rec"].get("type", "")) == "ocean":
			pk = k
	v.select(pk)
	v.yaw = 0.5
	v._yaw_t = 0.5
	v.pitch = -0.6
	v._pitch_t = -0.6
	v.fit(true)
	mp._update_info()
	await _snap("map3d", 2.5)
	c._computer.show_tab(2)
	for i in 20:
		await process_frame
	var gp: Node = c._computer.maps().sub(2)
	gp.select("kyros")
	gp._plot_route()
	gp._view.yaw = 0.4
	gp._view._yaw_t = 0.4
	gp._view.snap_to(gp._view.at("lachesis"), 1250.0)
	await _snap("galaxy3d", 2.5)
	c._computer.close()
	galaxy.route = []


## The Automaton's planet map on Knossos's ocean world: on foot in its city,
## a walk and a flight's worth of it explored (the rest under the fog), its
## towns, caves and camps marked where seen - then the city's plan, its
## places named.
func _planet_map3d() -> void:
	galaxy.new_game(false)
	galaxy.current_system = galaxy.HOME
	load("res://scripts/world/space/cosmos.gd").arrive_from = ""
	await _set_scene(load("res://scenes/world/cosmos.tscn").instantiate())
	var c: Node = _scene
	while not c.build_settled():
		await process_frame
	c.ship.control = false
	var pl: Node3D = null
	for p in c.planets:
		if str(p.rec.get("type", "")) == "ocean" and not p.towns.is_empty():
			pl = p
	if pl == null:
		return
	var tk := 0
	for n in pl.towns.size():
		if str(pl.towns[n]["kind"]) == "city":
			tk = n
	var site: Dictionary = pl.towns[tk]
	var pid := str(pl.rec.get("id", ""))
	var ocean: int = c.planets.find(pl)
	c.warp_to(ocean, 40.0, 0.0, 0.0, c.land_up(ocean))
	c.land()
	for i in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	var w: Node3D = c.walker
	var txf: Transform3D = load("res://scripts/world/life/cosmos_town.gd").frame(site, pl.radius)
	w.drive = {}
	w.set_deck(null)
	w.planet = pl
	w.global_position = pl.global_position + txf * Vector3(60, 0.3, 10)
	w.velocity = Vector3.ZERO
	# What's been explored: a flight's track over the world, and the city walked.
	var d0: Vector3 = site["dir"]
	var ax: Vector3 = d0.cross(Vector3.UP).normalized()
	for k in 30:
		galaxy.reveal_planet(pid, d0.rotated(ax, k * 0.035).rotated(d0, 0.3 * sin(k * 0.4)), 1000.0 / pl.radius)
	for k in 10:
		galaxy.reveal_planet(pid, d0.rotated(Vector3.UP, -k * 0.05), 800.0 / pl.radius)
	galaxy.visit_town(pid, str(site["name"]))
	c.open_computer(1)
	for i in 10:
		await process_frame
	var mp: Node = c._computer.maps()
	mp.show_sub(0)
	var pm: Node = mp.sub(0)
	for i in 600:
		await process_frame
		if pm._view._globe.mesh is ArrayMesh:
			break
	var v: Node = pm._view
	v.turn_to(d0.rotated(ax, 0.25), 200.0)   # (twice the globe's radius)
	v.pitch = v._pitch_t
	v.yaw = v._yaw_t
	v.dist = v._dist_t
	v.rebuild()
	v.select("town:%d" % tk)
	pm._update_info()
	await _snap("planet3d", 2.5)
	pm.open_plan("town:%d" % tk)
	await _snap("town_plan3d", 2.5)
	c._computer.close()


func _any(ids: Array) -> bool:
	return ids.any(func(i): return i in _want)


## Mining in Klotho's asteroid field: a rock scanned, its veins marked, the
## beam on one, its heat held in the green (a pulse a frame by its heat).
func _mining3d() -> void:
	galaxy.current_system = "klotho"
	load("res://scripts/world/space/cosmos.gd").arrive_from = ""
	await _set_scene(load("res://scenes/world/cosmos.tscn").instantiate())
	var c: Node = _scene
	while not c.build_settled():
		await process_frame
	c.ship.control = false
	for x in c.npc_ships:
		if is_instance_valid(x):
			x.queue_free()
	c.npc_ships.clear()
	c._pirate_cd = 9999.0
	var f: Node3D = c.fields[0]
	var i := 0
	for k in f.rocks.size():
		if f.rocks[k][1] > f.rocks[i][1] and f.rocks[k][1] < 40.0:
			i = k
	var at: Vector3 = f.to_global(f.rocks[i][0])
	var r: float = f.rocks[i][1]
	c.ship.global_position = at + Vector3(r * 0.6, r * 1.6, r + 80.0)
	c.ship.look_at(at, Vector3.UP)
	c.cam._q = c.ship.global_basis.get_rotation_quaternion()
	var m: Node = c.mining
	m.lock(f, i)
	for k in 200:   # (scanned)
		await process_frame
		if m.rock_state()["scanned"]:
			break
	var st: Dictionary = m.rock_state()
	var best := -1
	var bs := -1.0
	var to_ship: Vector3 = (c.ship.global_position - at).normalized()
	for k in st["veins"].size():   # (a vein facing the ship but off to its side: the beam in sight)
		var dv: Vector3 = f.vein_at(i, st["veins"][k]) - at
		if dv.normalized().dot(to_ship) < 0.2:
			continue
		var side: float = (dv - to_ship * dv.dot(to_ship)).length()
		if side > bs:
			bs = side
			best = k
	m.vein = best
	var pv: Dictionary = st["veins"][best]   # (half of it cut already: its pit sunk into the rock)
	pv["units"] = int(int(pv["max"]) * 0.5)
	m._pit(st, pv)
	var pulse := func() -> void:
		if is_instance_valid(c) and m.vein >= 0:
			c.ship.drive = {"fire": float(st["veins"][m.vein]["heat"]) < 0.72}
	process_frame.connect(pulse)
	for k in 200:
		await process_frame
	process_frame.disconnect(pulse)
	st["veins"][m.vein]["heat"] = 0.35   # (then held on: in the green when it's taken)
	c.ship.drive = {"fire": true}
	await _snap("space3d_mining", 1.0)
	c.ship.drive = {}


## Mining on foot: by a deposit (the biggest near), the beam on it, its heat rising.
## The scanner's pulse over a vein: its ghost through the ground, its mark (name, units, depth).
func _vein3d(c: Node) -> void:
	var w: Node3D = c.walker
	var t0 := Time.get_ticks_msec()
	while c.veins.veins.is_empty() and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	if c.veins.veins.is_empty():
		return
	var pl: Node3D = c.veins.planet
	var v: Dictionary = c.veins.veins.values()[0]
	for vv: Dictionary in c.veins.veins.values():   # (a coloured ore - not the white salt or ice)
		if not str(vv["mineral"]) in ["salt", "ice"]:
			v = vv
			break
	var pts: Array = v["pts"]
	var mid: Vector3 = (pts[0] + pts[pts.size() - 1]) * 0.5
	var u: Vector3 = mid.normalized()
	var along: Vector3 = ((pts[pts.size() - 1] as Vector3) - (pts[0] as Vector3))
	along = (along - u * along.dot(u)).normalized()
	var side: Vector3 = u.cross(along).normalized()
	var spot: Vector3 = mid - side * 2.5   # (beside it, looking across: you in front of its glow on the ground)
	spot = spot.normalized() * (pl.radius + w.floor_at(spot) + 0.05)
	w.global_position = pl.global_position + spot
	w.heading = side
	c.cam.foot_zoom = 1.25
	c.cam._pitch = 0.42
	for cr in c.creatures:
		cr.global_position += u * 0.0 + side * 400.0   # (the animals out of the shot)
	for i in 20:
		await process_frame
	c.target = null
	c.sandbox.scan()
	await _snap("space3d_vein", 2.0)


## Diving: under the sea of the ocean world - the water's look, its floor's life.
func _underwater3d(c: Node) -> void:
	var w: Node3D = c.walker
	var pl: Node3D = w.planet
	var d0: Vector3 = (w.global_position - pl.global_position).normalized()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var wet := Vector3.ZERO
	for i in 8000:
		var u := (d0 + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.8).normalized()
		var hh: float = pl.shape.height(u)
		if hh < -7.5 and hh > -10.0:   # (an 8-10 m floor: the kelp's depth, in the light)
			wet = u
			break
	if wet == Vector3.ZERO:
		return
	w.global_position = pl.global_position + wet * (pl.radius - 1.25)
	w.velocity = Vector3.ZERO
	for i in 10:
		await process_frame
	w.drive = {"move": Vector2.ZERO, "dive": true}
	for i in 90:
		await process_frame
	w.drive = {"move": Vector2(0, 0.6)}
	c.cam._pitch = 0.4
	for i in 60:
		await process_frame
	c.target = null
	await _snap("space3d_underwater", 2.5)
	w.drive = {}


func _dig3d(c: Node) -> void:
	var w: Node3D = c.walker
	var t0 := Time.get_ticks_msec()
	while (c.deposits == null or c.deposits.deps.is_empty()) and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	if c.deposits == null or c.deposits.deps.is_empty():
		return
	var dp: Node = c.deposits
	var best: Dictionary = {}
	for k in dp.deps:   # (the biggest crystal near, else the biggest)
		var d: Dictionary = dp.deps[k]
		var cr: bool = dp.LOOK.get(d["mineral"], [0, 0, 0, false])[3]
		var score: float = float(d["size"]) + (2.0 if cr else 0.0)
		if best.is_empty() or score > float(best.get("_s", 0.0)):
			best = d
			best["_s"] = score
	var sp: Array = dp._sphere(best)
	var u: Vector3 = best["up"]
	var side: Vector3 = u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).normalized()
	var right: Vector3 = (-side).cross(u).normalized()
	var spot: Vector3 = (sp[0] as Vector3) + side * (float(sp[1]) + 3.2) - right * 0.55 - w.planet.global_position
	w.global_position = w.planet.global_position + spot.normalized() * (w.planet.radius + w.floor_at(spot) + 0.05)
	w.heading = -side
	c.cam.foot_zoom = 1.0
	var drop: float = (w.global_position + u * 1.55 - (sp[0] as Vector3)).dot(u)
	c.cam._pitch = atan2(drop, float(sp[1]) + 3.2 + 4.6)
	for cr in c.creatures:
		cr.global_position += u * 0.0 + side * 400.0   # (the animals out of the shot)
	for i in 20:
		await process_frame
	w.drive = {"fire": true}
	await _snap("space3d_dig", 2.6)
	w.drive = {}


## Digging: the terrain digger out, a hole cut down into the ground ahead, the beam in it.
func _digging3d(c: Node) -> void:
	var w: Node3D = c.walker
	var u: Vector3 = w.up()
	var pl: Node3D = w.planet
	var side: Vector3 = w.heading.cross(u).normalized()
	var spot: Vector3 = w.global_position + side * 40.0 - pl.global_position   # (open ground, off the last shot's deposit: no tree near)
	for tries in 12:
		var clear := true
		for rk in pl.rocks_near(spot, 26.0):
			if float(rk[2]) > 2.0:
				clear = false
		if c.ship and (pl.global_position + spot).distance_to(c.ship.global_position) < 70.0:
			clear = false   # (nor your ship's hull at the edge of the picture)
		if clear:
			break
		spot += side * 17.0
	w.global_position = pl.global_position + spot.normalized() * (pl.radius + w.floor_at(spot) + 0.05)
	w.velocity = Vector3.ZERO
	for i in 30:
		await process_frame
	var dp: Node = c.deposits
	dp.deps.clear()
	for k in dp.get_children():
		if k is MeshInstance3D and k.material_override == dp._mat:
			k.queue_free()
	if not dp.digger:
		dp.toggle_digger()
	w.heading = -w.heading   # (away from the trees: the pit in the sun)
	c.cam.foot_zoom = 1.25
	c.cam._pitch = 0.5
	for i in 20:
		await process_frame
	w.drive = {"fire": true}
	var h0: Vector3 = w.heading
	for i in 300:   # (five seconds of digging, swept from side to side: a trench; its heat kept down)
		dp.heat = minf(dp.heat, 0.5)
		w.heading = h0.rotated(u, sin(i / 300.0 * TAU) * 0.5)
		await process_frame
	w.heading = h0
	w.global_position -= h0 * 3.0   # (back from the edge, looking down into it)
	c.cam._pitch = 0.62
	c.cam.foot_zoom = 1.0
	w.drive = {}
	var vx: Node = w.planet.voxels   # (the carved ground meshed: the shot shows it all)
	var t0 := Time.get_ticks_msec()
	while vx and vx.building() and Time.get_ticks_msec() - t0 < 15000:
		await process_frame
	w.drive = {"fire": true}
	dp.heat = 0.55
	c.target = null   # (nor the planet's window over the pit)
	await _snap("space3d_digging", 0.3)
	w.drive = {}
	if dp.digger:
		dp.toggle_digger()   # (the rifle again: the next shots aren't the digger's)
	c.target = null          # (nor the target's window, in the town's)


## Building: a Minoan house put up on open ground by the builder (BuildKit's
## pieces) - foundations, walls, a door and windows, a porch of red columns
## under a triangle roof, front steps, a brazier inside - and the builder in
## hand, a window's preview green on the house's open edge.
func _building3d(c: Node) -> void:
	var CB = load("res://scripts/world/build/cosmos_builds.gd")
	var BK = load("res://scripts/world/build/build_kit.gd")
	var TU = load("res://scripts/ui/toolbar_use.gd")
	var w: Node3D = c.walker
	var pl: Node3D = w.planet
	var u: Vector3 = w.up()
	var side: Vector3 = w.heading.cross(u).normalized()
	var spot: Vector3 = w.global_position - side * 70.0 - pl.global_position
	var start := spot
	var best_v := INF
	var best := spot
	for tries in 80:   # (open, level ground above the sea, no tree near: the most level of those tried)
		var cand: Vector3 = start + side.rotated(u, tries * 2.4) * (tries * 8.0)
		var h0: float = pl.shape.height(cand.normalized())
		if h0 < 1.2 or pl.shape.cleared(cand.normalized()):
			continue
		var tree := false
		for rk in pl.rocks_near(cand, 22.0):
			if float(rk[2]) > 2.0:
				tree = true
		if tree:
			continue
		var worst := 0.0
		for k in 16:
			var q: Vector3 = cand + side.rotated(u, k * TAU / 16.0) * (8.0 + 6.0 * (k % 2))
			worst = maxf(worst, absf(pl.shape.height(q.normalized()) - h0))
		if worst < best_v:
			best_v = worst
			best = cand
	spot = best
	CB.give({"stone": 400, "timber": 100, "marble": 100, "bronze_ingots": 50})
	var b: Node = c.builds
	b._sync_t = 1e9
	b.planet = pl
	var at: Vector3 = pl.global_position + spot.normalized() * (pl.radius + pl.shape.height(spot.normalized()))
	b.aim_frame = b.new_frame(at, w.heading)
	b.aim_frame.origin += b.aim_frame.basis.y * b._new_top(at, b.aim_frame, "sq")
	w.global_position = pl.global_transform * (b.aim_frame * Vector3(3.0, 1.0, 2.0))   # (in the middle of the plot while it's built: every piece within the builder's reach)
	w.velocity = Vector3.ZERO
	var P := func(t: String, p: Vector3, r := 0) -> Dictionary:
		return {"t": t, "p": [p.x, p.y, p.z], "r": r, "m": 1, "s": "minoa", "c": 0}
	b.place(null, P.call("foundation", Vector3.ZERO), true)
	var st: Node = b.structures[-1]
	for q in [Vector3(4, 0, 0), Vector3(8, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 4), Vector3(8, 0, 4)]:
		b.place(st, P.call("foundation", q), true)
	var tri: Dictionary = st.plan.snap("foundation_tri", Vector3(-3.0, 0, 2.0))
	b.place(st, tri.merged({"m": 1, "s": "minoa", "c": 0}), true)
	var keys := {}
	for p in st.plan.pieces:
		if str(p["t"]) == "foundation":
			for e in BK.edges(p):
				keys[BK.key(e[2])] = int(keys.get(BK.key(e[2]), 0)) + 1
	for p in st.plan.pieces.duplicate():
		if str(p["t"]) != "foundation":
			continue
		for e in BK.edges(p):
			var m: Vector3 = e[2]
			if int(keys[BK.key(m)]) > 1 or (m.x < -1.0 and m.z > 3.0) or (m.z < -1.0 and absf(m.x) < 0.1):
				continue   # (open to the porch; the front's left window left for the builder)
			var t := "wall"
			if m.z < -1.0:
				t = "door" if absf(m.x - 4) < 0.1 else "window"
			elif m.z > 5.0 and absf(m.x - 4) < 0.1:
				t = "window"
			elif m.x > 9.0 and m.z > 3.0:
				t = "arch"
			b.place(st, P.call(t, m, BK.r_facing(e[3])), true)
	b.place(st, st.plan.snap("steps", Vector3(4, -0.3, -2.8)).merged({"m": 1, "s": "minoa", "c": 0}), true)
	var tri_at: int = st.plan.pieces.find_custom(func(p): return str(p["t"]) == "foundation_tri")
	for q in BK.corners(st.plan.pieces[tri_at]):
		b.place(st, P.call("pillar", q), true)
	for q in [Vector3(0, 0, 0), Vector3(4, 0, 0), Vector3(8, 0, 0), Vector3(0, 0, 4), Vector3(4, 0, 4), Vector3(8, 0, 4)]:
		b.place(st, P.call("floor", q + Vector3(0, BK.WALL_H, 0)), true)
	b.place(st, {"t": "roof_tri", "p": [tri["p"][0], BK.WALL_H, tri["p"][2]], "r": tri["r"], "m": 1, "s": "minoa", "c": 0}, true)
	for k in 3:
		b.place(st, P.call("railing", Vector3(k * 4.0, BK.WALL_H, -2.0), 6), true)
	b.place(st, P.call("lamp", Vector3(2.0, 0, 1.0)), true)
	b.place(st, P.call("pithos", Vector3(9.0, BK.WALL_H, 5.0)), true)
	b.place(st, P.call("lamp", Vector3(1.0, BK.WALL_H, 1.0)), true)
	var fr: Transform3D = st.global_transform
	var wl: Vector3 = fr * Vector3(-1.0, 0.0, -11.5) - pl.global_position
	w.global_position = pl.global_position + wl.normalized() * (pl.radius + w.floor_at(wl) + 0.05)
	w.velocity = Vector3.ZERO
	w.heading = (fr.basis * Vector3(0.12, 0, 1)).normalized()
	w.facing = w.heading
	c.cam.foot_zoom = 1.3
	c.cam._pitch = 0.2
	CB.piece = "window"
	CB.tier = 1
	CB.style = "minoa"
	CB.mode = "place"
	TU._held = "tool:build"
	c.target = null
	var t0 := Time.get_ticks_msec()
	while (st.busy() or not w.on_ground) and Time.get_ticks_msec() - t0 < 10000:
		await process_frame
	await _snap("space3d_building", 2.0)
	TU._held = "tool:rifle"


## Saves the screen as shot `id` (when it's wanted), after `wait` seconds.
func _snap(id: String, wait := 1.5) -> void:
	if not id in _want:
		return
	var t_end := Time.get_ticks_msec() + int(wait * 1000.0)
	while Time.get_ticks_msec() < t_end:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(id + ".png"))
	_done.append(id)


## The 3D preview (Cosmos): an ocean world from its sky, then low over its coast.
func _space3d() -> void:
	galaxy.current_system = galaxy.HOME
	load("res://scripts/world/space/cosmos.gd").arrive_from = ""
	await _set_scene(load("res://scenes/world/cosmos.tscn").instantiate())
	var c: Node = _scene
	while not c.build_settled():
		await process_frame
	c.ship.control = false
	var ocean := 0
	for i in c.planets.size():
		if str(c.planets[i].rec.get("type", "")) == "ocean":
			ocean = i
			break
	c.warp_to(ocean, 1800.0, 0.55, 0.55)
	c.ship.drive = {"throttle": 0.35}
	c.target = c.planets[ocean]
	await _snap("space3d", 3.0)
	c.warp_to(ocean, 45.0, 0.75)
	c.ship.drive = {"throttle": 0.5}
	c.hud.show_help = false
	await _snap("space3d_ground", 3.0)
	# Landed, on foot among the plants and animals.
	c.warp_to(ocean, 40.0, 0.0, 0.0, c.land_up(ocean))
	c.land()
	for i in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	var wk: Node3D = c.walker   # (out from under the ship: 25 m off, facing on)
	var wu: Vector3 = wk.up()
	var away: Vector3 = wk.global_position - c.ship.global_position
	away = (away - wu * away.dot(wu)).normalized()
	var spot: Vector3 = wk.global_position + away * 25.0 - wk.planet.global_position
	wk.global_position = wk.planet.global_position + spot.normalized() * (wk.planet.radius + wk.floor_at(spot) + 0.05)
	wk.heading = away
	c.cam.foot_zoom = 1.6
	for i in 8:
		c._life()
	var w: Node3D = c.walker
	var k := 0
	for cr in c.creatures:
		cr.global_position = w.global_position + w.heading * (14.0 + k * 3.0) + w.heading.cross(w.up()) * (k - 3) * 4.0
		k += 1
	c.hud.show_help = true
	await _snap("space3d_foot", 2.5)
	if "space3d_dig" in _want:
		await _dig3d(c)
	if "space3d_digging" in _want:
		await _digging3d(c)
	if "space3d_building" in _want:
		await _building3d(c)
	if "space3d_vein" in _want:
		await _vein3d(c)
	if "space3d_underwater" in _want:
		await _underwater3d(c)
	# A town: the palace's court, its colonnade, the people.
	var ti := -1
	var tk := 0   # (the town most in daylight, of any planet)
	var best := -2.0
	for pi in c.planets.size():
		for n in c.planets[pi].towns.size():
			var sun: float = (c.planets[pi].towns[n]["dir"] as Vector3).dot(c.planets[pi].sun_dir)
			print("TOWN %s %s sun %.2f" % [c.planets[pi].name, c.planets[pi].towns[n]["name"], sun])
			if sun > best:
				best = sun
				ti = pi
				tk = n
	if ti >= 0:
		var tpl: Node3D = c.planets[ti]
		var txf: Transform3D = load("res://scripts/world/life/cosmos_town.gd").frame(tpl.towns[tk], tpl.radius)
		w.drive = {}
		w.set_deck(null)
		w.planet = tpl
		w.global_position = tpl.global_position + txf * Vector3(8, 0.3, 4)
		w.heading = (tpl.global_basis * txf.basis) * Vector3(-1, 0, -0.35).normalized()
		w.velocity = Vector3.ZERO
		for i in 300:
			c._towns_tick()
			await process_frame
			var tw = c._towns.get(tpl, [null, null, null])[tk]
			if tw and tw.built and c.citizens.size() >= 6:
				break
		for x in c.creatures:
			if is_instance_valid(x):
				x.queue_free()
		var tw2 = c._towns.get(tpl, [])[tk]
		var people: Array = c.citizens.filter(func(x): return x.town == tw2 and not x.role in ["vendor", "courier", "pilot"])
		for n in mini(people.size(), 5):   # (a few of its people in view)
			people[n].global_position = tw2.to_global(Vector3(-2.0 - n * 2.6, 0.0, 1.0 - (n % 2) * 3.0 - n))
		c.cam.foot_zoom = 2.2
		c.sandbox.scan_marks = []   # (an earlier shot's scan: its labels not over the court)
		c.target = null
		await _snap("space3d_town", 3.0)
		# Its people up close: the ore buyer by the landing field, a guard, the androids.
		var kil: Array = c.citizens.filter(func(x): return x.town == tw2 and x.role == "vendor")
		if not kil.is_empty():
			var kp: Vector3 = tw2.to_local(kil[0].global_position)
			var crew: Array = []
			for want_w in ["rifle", "bow", "axe"]:
				var one: Array = c.citizens.filter(func(x): return x.town == tw2 and x.model_id == "minoan" and x.weapon == want_w)
				if not one.is_empty():
					crew.append(one[0])
			var gd: Array = c.citizens.filter(func(x): return x.town == tw2 and x.model_id == "guard")
			if not gd.is_empty():
				crew.append(gd[0])
			var me_tl: Vector3 = kp + Vector3(0.5, 0.0, 6.0)
			for n in crew.size():
				var at_tl: Vector3 = kp + Vector3(-1.6 - n * 1.5, 0.0, 2.0 + (n % 2) * 1.4)
				crew[n]._wait = 99.0
				crew[n].global_position = tw2.to_global(at_tl)
				crew[n].facing = (me_tl - at_tl).normalized()   # (turned to you)
			kil[0].facing = (me_tl - kp).normalized()
			w.global_position = tw2.to_global(me_tl + Vector3(0, 0.3, 0))
			w.heading = (tw2.global_basis * Vector3(-0.45, 0, -1)).normalized()
			c.cam.foot_zoom = 0.62
			await _snap("space3d_people", 3.0)
		# Inside: the palace's throne room (its throne, the griffins painted behind it).
		w.global_position = tw2.to_global(Vector3(-27.5, 0.2, -15.15))
		w.heading = (tw2.global_basis * Vector3(-1, 0, 0.12)).normalized()
		w.velocity = Vector3.ZERO
		c.cam.foot_zoom = 0.55
		for i in 10:
			await process_frame
		await _snap("space3d_inside", 2.0)
		# Below: a dungeon's dead, then a cave.
		for kind in ["dungeon", "cave"]:
			var site: Dictionary = {}
			for e in c.dungeons_of(tpl):
				if e[0]["kind"] == kind:
					site = e[0]
			if site.is_empty():
				continue
			c.enter_dungeon(site)
			for i in 300:
				await process_frame
				if c.dungeon and c.dungeon.built and w.deck == c.dungeon:
					break
			var dg = c.dungeon
			var room: Rect2 = dg.rooms[1][0] if dg.rooms.size() > 1 else dg.rooms[0][0]
			var me_at := Vector3(room.position.x + 2.8, 0.05, room.end.y - 2.8)   # (by a corner, looking across the room)
			w.global_position = dg.to_global(me_at)
			w.set_deck(dg)
			w.heading = (dg.global_basis * Vector3(1, 0, -1)).normalized()
			w.facing = w.heading
			w.hp = 100000.0
			var foes: Array = c.npcs.filter(func(x): return x.get("dungeon") == dg)
			var picks: Array = foes.filter(func(x): return x.role == "skeleton").slice(0, 2) + foes.filter(func(x): return x.role == "demon").slice(0, 1)
			for n in picks.size():
				var pose_at := Vector3(room.get_center().x + (n - 1) * 2.2, 0.0, room.get_center().y + (n - 1) * 1.2)
				picks[n].global_position = dg.to_global(pose_at)
				picks[n].facing = (me_at - pose_at).normalized()
				picks[n].global_basis = Basis.looking_at(dg.global_basis * picks[n].facing, dg.global_basis.y)
				picks[n].set_process(false)   # (posed for the picture: upright on its floor, turned to you)
			c.cam.foot_zoom = 0.7
			for i in 20:
				await process_frame
			await _snap("space3d_" + kind, 1.5)
			for x in picks:
				if is_instance_valid(x):
					x.set_process(true)
			c.leave_dungeon()
			w.hp = 100.0
		w.planet = c.planets[ocean]
		c.embark()
	# A pirate raid in space.
	c.board()
	c.ship.take_off()
	for i in 90:
		await process_frame
	c.warp_to(ocean, 9000.0, 0.6)
	c._life_rng.seed = 3
	c._pirate_cd = 0.0
	c._traffic()
	for x in c.npc_ships:
		if is_instance_valid(x) and x.kind == "pirate":
			c.target = x
			x.global_position = c.ship.global_position - c.ship.global_basis.z * 900.0 + c.ship.global_basis.x * 60.0 + c.ship.global_basis.y * 40.0
			x.set_process(false)   # (held still for the picture: where the notes point)
	c.ship.drive = {"fire": true}
	for i in 40:
		await process_frame
	await _snap("space3d_fight", 1.0)
	for x in c.npc_ships:
		if is_instance_valid(x):
			x.set_process(true)
	c.ship.drive = {}
	# A space monster at its lair.
	if not c.lairs.is_empty():
		for x in c.npc_ships:
			if is_instance_valid(x):
				x.queue_free()
		c.npc_ships.clear()
		var lr: Node3D = c.lairs[0]
		c.ship.global_position = lr.global_position + Vector3(900, 120, 300)
		c.ship.look_at(lr.global_position, Vector3.UP)
		c.cam._q = c.ship.global_basis.get_rotation_quaternion()
		c._lairs_tick()
		var mon = lr.monster
		for i in 200:
			await process_frame
			if mon and mon.built:
				break
		mon.global_position = c.ship.global_position - c.ship.global_basis.z * mon.length * 1.6
		mon.look_at(c.ship.global_position, Vector3.UP)
		c.target = mon
		await _snap("space3d_monster", 2.5)
	# Docked: the hangar.
	for x in c.npc_ships:
		if is_instance_valid(x):
			x.queue_free()
	c.npc_ships.clear()
	c._pirate_cd = 9999.0
	c._place_ship()
	c.dry_run = true
	# Manual docking: over the pad the station gave you, coming down on the thrusters.
	c.request_dock()
	var st: Node3D = c.dock_station
	var xf: Transform3D = st.pad_transform(c.dock_pad)
	var out: Vector3 = (xf.origin - st.global_position)
	out = (out - xf.basis.y * out.dot(xf.basis.y)).normalized()
	var at: Vector3 = xf.origin + xf.basis.y * 75.0 + out * 170.0
	c.ship.global_transform = Transform3D(c._level(-out, xf.basis.y), at)
	c.ship.velocity = Vector3.ZERO
	c.ship.drive = {"throttle": 0.03, "lift": -0.1}
	c.cam.follow(1.0)
	await _snap("space3d_pad", 2.0)
	c.ship.drive = {}
	c.request_dock(true)
	while not (c.docked and c._dock.is_empty()):
		await process_frame
	var h = c.hangar
	while not (h.built and h._spawned >= h._staff.size()):
		await process_frame
	c.disembark()   # (down the ramp onto the port's hall)
	# (out from the ship's side toward the concourse: the hall's wall, its doors and windows, the ship behind)
	var foot: Vector3 = h.to_local(c.walker.global_position)
	c.walker.global_position = h.to_global(Vector3(h.xa - 38.0, 0, foot.z + 14.0))
	c.walker.set_deck(h)
	c.walker.heading = h.global_basis.x
	c.cam.foot_zoom = 2.2
	c.cam._pitch = 0.08   # (level: the wall's height, its doors and windows)
	for i in 30:
		await process_frame
	await _snap("space3d_hangar", 2.5)
	# The bar: its keeper, E to talk.
	var bt: Dictionary = h.people.filter(func(q): return q["role"] == "bartender")[0]
	var bn: Node3D = bt["node"]
	c.walker.global_position = h.to_global(bn.position + Vector3(-1.0, 0, 3.6))
	c.walker.set_deck(h)
	c.walker.heading = h.global_basis * Vector3(0.35, 0, -1).normalized()
	c.cam.foot_zoom = 2.0
	c.cam._pitch = 0.2
	for i in 30:
		await process_frame
	await _snap("space3d_port", 2.0)
	# Aboard a trader down on this platform's lift: its hold, the doorway on to its quarters.
	var NpcShip = load("res://scripts/world/space/cosmos_npc_ship.gd")
	var st2 = h.station
	var pd = null
	for p in st2.pads:
		if int(p.get("platform", -1)) == h.platform and (p.get("owner") == null or not is_instance_valid(p.get("owner"))):
			pd = p
	if pd != null:
		var tr = NpcShip.new()
		tr.setup("trader", c, 3, "minoa")
		c.world.add_child(tr)
		tr.park(st2, pd)
		tr._pad_stay = 9999.0
		c.npc_ships.append(tr)
		var inn = tr.make_interior()
		while not inn.built:
			await process_frame
		if inn.ok:
			var hold: Array = inn.rooms[inn.rooms.size() - 1]
			c.walker.global_position = inn.to_global(Vector3(0, inn.sill, float(hold[1]) + 5.0))
			c.walker.set_deck(inn)
			c.walker.heading = -tr.global_basis.z
			c.walker.facing = -tr.global_basis.z   # (its back to you: looking on into the ship)
			c.cam.foot_zoom = 1.0
			c.cam._pitch = 0.12
			for i in 40:
				await process_frame
			await _snap("space3d_trader", 2.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## A new game's start: on foot on Amnissos by a city's landing field - its ore buyer,
## courier's office and local pilot beside you - the tutorial's panel, the scanner's marks.
func _start3d() -> void:
	var CG = load("res://scripts/world/game/cosmos_game.gd")
	CG.ensure()   # (a game first: the scene would make a fresh one, without the start)
	var keep: Dictionary = CG.extra.duplicate(true)
	CG.start_on_foot()
	galaxy.current_system = galaxy.HOME
	load("res://scripts/world/space/cosmos.gd").arrive_from = ""
	await _set_scene(load("res://scenes/world/cosmos.tscn").instantiate())
	var c: Node = _scene
	while not c.build_settled():
		await process_frame
	for i in 240:   # (the city built round you, its people out)
		await process_frame
		if c.citizens.filter(func(x): return is_instance_valid(x) and x.role in ["vendor", "courier", "pilot"]).size() >= 3:
			break
	c.walker.heading = -c.walker.heading
	c.cam.foot_zoom = 2.4
	c.cam._pitch = 0.15
	for i in 30:
		await process_frame
	c.sandbox.scan()
	await _snap("space3d_start", 2.5)
	CG.extra = keep


func _set_scene(n: Node) -> void:
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








