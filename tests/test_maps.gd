extends TestCase
## The galaxy (120 systems through a 3D volume, its lanes, the bake), the
## galaxy map's fog of war and course planner, and the Automaton's 3D
## maps (the solar map, the galaxy map).


func setup() -> void:
	Galaxy.new_game(false, true)


func test_galaxy_has_120_systems_in_six_empires() -> void:
	check_eq(Galaxy.SYSTEMS.size(), 120, "systems")
	var count := {}
	for id in Galaxy.SYSTEMS:
		var o: String = Galaxy.SYSTEMS[id]["owner"]
		count[o] = int(count.get(o, 0)) + 1
	for e in Galaxy.EMPIRE_SIZE:
		check_eq(int(count.get(e, 0)), Galaxy.EMPIRE_SIZE[e], e + " systems")
	check_eq(int(count.get("pirates", 0)), Galaxy.PIRATE_DENS, "Sea Peoples' dens")
	# The hand-made heart kept as it was (the story's systems, ids saves use).
	check_eq(Galaxy.SYSTEMS["atrapos"]["name"], "Knossos", "Knossos is home")
	check_eq(Galaxy.SYSTEMS["atrapos"]["owner"], "minoa", "Knossos is Minoan")
	for id in Galaxy.BASE_SYSTEMS:
		check(Galaxy.SYSTEMS.has(id), "kept: " + id)
		check((Galaxy.SYSTEMS[id]["pos"] as Vector2).is_equal_approx(Galaxy.BASE_SYSTEMS[id]["pos"]), "same place on the old map: " + id)
	for id in ["g1_sitia", "g20_naxia", "g41_elis"]:
		check(Galaxy.SYSTEMS.has(id), "the first round's systems kept: " + id)


func test_names_never_repeat() -> void:
	var names := {}
	for id in Galaxy.SYSTEMS:
		var n: String = Galaxy.SYSTEMS[id]["name"]
		check(not names.has(n), "one system called " + n)
		names[n] = true
		check(not n.right(1).is_valid_int(), "a real place's name, not a number: " + n)
	for pool in [Galaxy.PLANET_NAMES, Galaxy.STATION_ROOTS]:
		for e in pool:
			for n in pool[e]:
				check(not names.has(n), "no system named like a planet or station: " + n)


func test_spread_through_3d() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	var above := 0
	var below := 0
	for id in Galaxy.SYSTEMS:
		var p: Vector3 = Galaxy.SYSTEMS[id]["pos3"]
		check((Galaxy.SYSTEMS[id]["pos"] as Vector2).is_equal_approx(Vector2(p.x, p.z)), "pos is pos3 from above: " + id)
		lo = lo.min(p)
		hi = hi.max(p)
		if p.y > 150.0:
			above += 1
		elif p.y < -150.0:
			below += 1
	var span := hi - lo
	check(span.y > 900.0, "real height spread (%.0f)" % span.y)
	check(span.x > 1800.0 and span.z > 1500.0, "wide (%.0f x %.0f)" % [span.x, span.z])
	check(above >= 20 and below >= 20, "systems well above and below the middle plane (%d, %d)" % [above, below])
	# Apart from each other.
	var ids: Array = Galaxy.SYSTEMS.keys()
	var closest := INF
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			closest = minf(closest, (Galaxy.SYSTEMS[ids[i]]["pos3"] as Vector3).distance_to(Galaxy.SYSTEMS[ids[j]]["pos3"]))
	check(closest > 60.0, "no two systems on top of each other (%.0f)" % closest)


func test_lanes_connect_everything() -> void:
	var seen := {Galaxy.HOME: 0}
	var queue := [Galaxy.HOME]
	while not queue.is_empty():
		var c: String = queue.pop_front()
		for n in Galaxy.neighbors(c):
			if not seen.has(n):
				seen[n] = int(seen[c]) + 1
				queue.append(n)
	check_eq(seen.size(), 120, "every system reachable from Knossos")
	check(seen.values().max() <= 16, "no system too many jumps away (%d)" % seen.values().max())
	var longest := 0.0
	for l in Galaxy.LINKS:
		longest = maxf(longest, (Galaxy.SYSTEMS[l[0]]["pos3"] as Vector3).distance_to(Galaxy.SYSTEMS[l[1]]["pos3"]))
		check(l[0] != l[1], "a lane joins two systems")
	check(longest < 420.0, "lanes join near systems (longest %.0f)" % longest)
	# Gates in every system, none on top of another.
	for id in Galaxy.SYSTEMS:
		var gates: Dictionary = Galaxy.system(id)["gates"]
		check_eq(gates.size(), Galaxy.neighbors(id).size(), "a gate for every lane: " + id)
		var dirs: Array = gates.values()
		for i in dirs.size():
			check((dirs[i] as Vector2).length() > 1000.0, "a gate on the system's edge: " + id)
			for j in range(i + 1, dirs.size()):
				check((dirs[i] as Vector2).distance_to(dirs[j]) > 800.0, "gates apart in " + id)


func test_bake_is_current_and_fast() -> void:
	var fresh: Array = Galaxy.grow_fresh()
	check_eq(fresh[0].keys(), Galaxy.SYSTEMS.keys(), "the bake (data/galaxy.json) is the galaxy grown now - stale: godot --headless --path . -s tools/bake_galaxy.gd")
	check_eq(str(fresh[1]), str(Galaxy.LINKS), "the same lanes")
	var t := Time.get_ticks_usec()
	var g: GDScript = load("res://scripts/sim/galaxy.gd")
	var read: Array = g._read_layout()
	check(not read.is_empty(), "the bake reads back (its key matches)")
	check_lt((Time.get_ticks_usec() - t) / 1000.0, 30.0, "reading the bake (ms)")


func test_fog_of_war_and_routes() -> void:
	check(Galaxy.has_been(Galaxy.HOME), "Knossos counts as visited")
	check_eq(Galaxy.been.size(), 1, "only Knossos at the start")
	var n: String = Galaxy.neighbors(Galaxy.HOME)[0]
	check(Galaxy.is_known(n), "a neighbour known (its gate names it)")
	var far := ""
	for id in Galaxy.SYSTEMS:
		if not Galaxy.is_known(id):
			far = id
			break
	check(far != "", "systems beyond: unknown")
	check(Galaxy.find_known_route(Galaxy.HOME, far).is_empty(), "no route through systems you haven't been in")
	check_eq(Galaxy.find_known_route(Galaxy.HOME, n).size(), 2, "a route to the uncharted system next door")
	# Arriving: been there, the route moves on.
	var path := Galaxy.find_route(Galaxy.HOME, far)
	Galaxy.route = path
	Galaxy.current_system = path[1]
	check(Galaxy.has_been(path[1]), "arriving marks it visited")
	check_eq(Galaxy.route[0], path[1], "the route moves on from here")
	Galaxy.current_system = path[-1]
	check(Galaxy.route.is_empty(), "the route done at its end")
	# Saved and loaded.
	var d: Dictionary = Galaxy.get_save_data()
	Galaxy.load_save_data(JSON.parse_string(JSON.stringify(d)))
	check(Galaxy.has_been(path[1]) and Galaxy.has_been(path[-1]), "visited systems saved")
	# An old save (no "been"): the systems with a fog of their own count.
	d.erase("been")
	d["explored"] = {path[1]: ""}
	Galaxy.load_save_data(d)
	check(Galaxy.has_been(path[1]) and Galaxy.has_been(Galaxy.current_system), "an old save's visited systems")


func test_galaxy_map_page() -> void:
	var page: Control = load("res://scripts/ui/pages/galaxy_page.gd").new()
	page.size = Vector2(1500, 800)
	tree.root.add_child(page)
	await tree.process_frame
	page.refresh()
	for i in 3:
		await tree.process_frame
	var v: Node = page._view
	check(v.marks.has(Galaxy.HOME), "home on the map")
	for id in v.marks:
		check(Galaxy.is_known(id), "only what you know shows: " + id)
	check_eq(v.shown.size(), Galaxy.been.size(), "the systems shown: the ones visited")
	var n: String = Galaxy.neighbors(Galaxy.HOME)[0]
	check(v.stubs.has(n), "a stub to the uncharted neighbour")
	page.select(n)
	page._plot_route()
	check_eq(Galaxy.route, [Galaxy.HOME, n], "route plotted")
	check(page._plot.text == "Clear route", "the button clears it now")
	page._plot_route()
	check(Galaxy.route.is_empty(), "route cleared")
	page.add_to_route(n)
	check_eq(Galaxy.route.size(), 2, "a waypoint added")
	# The camera: zoom, turn, fit.
	var d0: float = v._dist_t
	v.zoom(0.5)
	check(v._dist_t < d0, "the wheel zooms in")
	v.fit(true)
	check(v.dist >= v.min_dist and v.dist <= v.max_dist, "fit within the zoom's range")
	page.queue_free()
	Galaxy.route = []


func test_solar_map_page() -> void:
	Galaxy.fog().reveal(Vector2.ZERO, 16000.0)   # (all of it swept)
	var page: Control = load("res://scripts/ui/pages/map_page.gd").new()
	page.size = Vector2(1500, 800)
	tree.root.add_child(page)
	await tree.process_frame
	page.refresh()
	for i in 3:
		await tree.process_frame
	var v: Node = page._view
	check(v.objs.has("star"), "the star")
	var planets: Array = v.objs.keys().filter(func(k): return v.objs[k]["kind"] == "planet")
	check_eq(planets.size(), Galaxy.HOME_ORBITS.size(), "every world of Knossos (swept)")
	check_eq(v.objs.keys().filter(func(k): return v.objs[k]["kind"] == "station").size(), Galaxy.system(Galaxy.HOME)["stations"].size(), "its stations")
	check_eq(v.objs.keys().filter(func(k): return v.objs[k]["kind"] == "gate").size(), Galaxy.neighbors(Galaxy.HOME).size(), "its gates")
	v.select(planets[0])
	page._update_info()
	check(page._info.text.contains(str(v.objs[planets[0]]["name"]).to_upper()), "the panel names it")
	check(page._info.text.contains("Radius"), "and tells about it")
	# The fog: a new system's dark - only the star.
	Galaxy.current_system = Galaxy.neighbors(Galaxy.HOME)[0]
	page.refresh()
	check(v.objs.has("star"), "the star always shows")
	check(v.objs.keys().all(func(k): return v.objs[k]["kind"] in ["star", "you", "gate"]), "the rest hidden in the fog")
	page.queue_free()


## The MAP tab's maps open centred on you - every time (MapsPage.show_sub:
## focus_you): the solar map on you, the galaxy map on your system; and the
## solar map's worlds placed each frame (fluid), from the galaxy's clock.
func test_maps_open_on_you() -> void:
	Galaxy.fog().reveal(Vector2.ZERO, 16000.0)
	var maps: Control = load("res://scripts/ui/pages/maps_page.gd").new()
	maps.size = Vector2(1500, 800)
	tree.root.add_child(maps)
	await tree.process_frame
	maps.show_sub(maps.SOLAR)
	await tree.process_frame
	var sv: Node = maps.sub(maps.SOLAR)._view
	var you: Vector3 = sv.objs[sv.you_key()]["pos"]
	check(sv.focus.distance_to(you) < 0.01, "the solar map opens on you (%.2f km off)" % sv.focus.distance_to(you))
	sv.pan(Vector2(400, 300))
	sv.snap()
	check(sv.focus.distance_to(you) > 1.0, "panned away")
	maps.show_sub(maps.GALAXY)
	await tree.process_frame
	var gv: Node = maps.sub(maps.GALAXY)._view
	var here: Vector3 = gv.at(Galaxy.current_system)
	check(gv.focus.distance_to(here) < 0.01, "the galaxy map opens on your system")
	gv.pan(Vector2(-500, 200))
	gv.snap()
	check(gv.focus.distance_to(here) > 1.0, "panned away")
	maps.show_sub(maps.SOLAR)
	check(sv.focus.distance_to(sv.objs[sv.you_key()]["pos"]) < 0.01, "the solar map again: on you again")
	maps.show_sub(maps.GALAXY)
	check(gv.focus.distance_to(here) < 0.01, "the galaxy again: on your system again")
	# Fluid: the worlds placed to the clock each frame, not four times a second.
	maps.show_sub(maps.SOLAR)
	var k: String = sv.objs.keys().filter(func(q): return sv.objs[q]["kind"] == "planet" and str(sv.objs[q]["rec"].get("moon_of", "")) != "")[0]
	var p0: Vector3 = sv.objs[k]["pos"]
	var t0: float = Galaxy.time
	Galaxy.time += 2.0
	sv._follow()
	var want: Vector3 = load("res://scripts/world/space/cosmos.gd").system_places(Galaxy.current_system, Galaxy.time)[k] / 1000.0
	check(sv.objs[k]["pos"].distance_to(want) < 0.001 and sv.objs[k]["pos"] != p0, "a moon placed to the clock between gatherings")
	check((sv._bodies[k] as Node3D).position.distance_to(want) < 0.001, "its sphere with it")
	check_eq(sv.anim_hz, Map3DView.frame_hz(), "the solar map drawn at the screen's rate")
	var tq := Time.get_ticks_usec()
	for i in 20:
		sv._follow()
	var ms := (Time.get_ticks_usec() - tq) / 20000.0
	print("  (the solar map's things placed in %.3f ms)" % ms)
	check_lt(ms, 1.0, "placing what moves a frame (ms)")
	Galaxy.time = t0
	maps.queue_free()


## A planet's fog of war (PlanetFog): revealed round you, kept in the save.
func test_planet_fog_of_war() -> void:
	var f := Galaxy.planet_fog("test_world")
	var d := Vector3(0.3, 0.5, 0.8).normalized()
	check(not f.explored(d), "a new world: all fog")
	check(Galaxy.reveal_planet("test_world", d, 0.12), "seeing the ground round you")
	check(f.explored(d), "where you are: explored")
	check(f.explored(d.rotated(Vector3.UP, 0.06)), "and round you")
	check(not f.explored(-d), "the far side still dark")
	check(not Galaxy.reveal_planet("test_world", d, 0.12), "nothing new the second time")
	# By the pole: the whole row round it.
	Galaxy.reveal_planet("test_world", Vector3(0.01, 1.0, 0.0).normalized(), 0.15)
	check(f.explored(Vector3(0.05, 1.0, 0.05).normalized()) and f.explored(Vector3(-0.05, 1.0, -0.05).normalized()), "the pole all round")
	Galaxy.visit_town("test_world", "Amnisos")
	var share := f.explored_share()
	check(share > 0.0 and share < 0.1, "a little of it explored (%.3f)" % share)
	var save: Dictionary = JSON.parse_string(JSON.stringify(Galaxy.get_save_data()))
	Galaxy.load_save_data(save)
	check(Galaxy.planet_fog("test_world").explored(d), "the fog comes back from the save")
	check(not Galaxy.planet_fog("test_world").explored(-d), "the dark too")
	check(Galaxy.town_visited("test_world", "Amnisos"), "the towns you've been in, saved")
	Galaxy.new_game(false, true)
	check(not Galaxy.planet_fog("test_world").explored(d), "a new game: fog again")


## The planet map (MAP > PLANET): a world's globe from its real ground, under
## its fog; its towns once seen; a visited town's plan with its places named.
func test_planet_map_page() -> void:
	var rec: Dictionary = {}
	for r in load("res://scripts/world/space/cosmos.gd").planet_records(Galaxy.HOME):
		if str(r.get("type", "")) == "ocean" and str(r.get("moon_of", "")) == "":
			rec = r
	check(not rec.is_empty(), "an ocean world in Knossos")
	var shape := PlanetShape.of(rec)
	var towns := CosmosTown.sites(shape, rec, Galaxy.owner_of(Galaxy.HOME))
	shape.set_flats(CosmosTown.flats_of(towns, shape.radius))
	check(not towns.is_empty(), "it has towns")
	var page: Control = load("res://scripts/ui/pages/planet_map_page.gd").new()
	page.source = {"rec": rec, "shape": shape, "towns": towns}
	page.size = Vector2(1500, 800)
	tree.root.add_child(page)
	await tree.process_frame
	var t0 := Time.get_ticks_usec()
	page.refresh()
	check_lt((Time.get_ticks_usec() - t0) / 1000.0, 8.0, "opening it (ms: the globe made on a worker)")
	var v: Node = page._view
	var pid := str(rec["id"])
	for i in 600:
		await tree.process_frame
		if PlanetMapPage._meshes.has(pid):
			break
	var m: Mesh = PlanetMapPage._meshes.get(pid)
	check(m != null, "the globe made")
	if m:
		check(m.get_faces().size() / 3 > 30000, "its ground in detail (%d triangles)" % (m.get_faces().size() / 3))
		check(v._globe.mesh == m, "shown")
	var tb := Time.get_ticks_usec()
	PlanetMapPage.build_globe(shape)
	var ms := (Time.get_ticks_usec() - tb) / 1000.0
	print("  (a globe made in %.0f ms on a worker)" % ms)
	check_lt(ms, 3000.0, "a globe's mesh made (ms, a worker's)")
	var tp := Time.get_ticks_usec()
	PlanetMapPage.bake_plan("city", 12345, "minoa")
	print("  (a city's plan drawn in %.0f ms on a worker)" % ((Time.get_ticks_usec() - tp) / 1000.0))
	check(v.all.keys().filter(func(k): return str(k).begins_with("town:")).is_empty(), "under the fog: no towns shown")
	# Seen: the town shows; walked in: its plan.
	var s: Dictionary = towns[0]
	Galaxy.reveal_planet(pid, s["dir"], 600.0 / shape.radius)
	v.follow()
	check(v.all.has("town:0"), "the town seen: on the map")
	check(not v.all["town:0"]["visited"], "seen, not visited")
	page.open_plan("town:0")
	check(not page.plan_shown(), "no plan of a town you haven't been in")
	# Not been in it: zooming in over it goes only as near as the globe goes.
	var td: Vector3 = PlanetMapPage.plan_centre_dir(s, shape.radius)
	v.turn_to(td, v.min_dist)
	await _wait(0.6)
	for i in 30:
		v.zoom(0.85)
		await tree.process_frame
	await _wait(1.0)
	check(v.span > v.span_floor() * 0.99 and page.plan_blend() == 0.0 and not page.plan_shown(), "an unvisited town: no plan - the globe as near as it goes")
	Galaxy.visit_town(pid, str(s["name"]))
	page.refresh()
	page.open_plan("town:0", true)
	check(page.plan_shown(), "a visited town: its plan")
	var key: String = PlanetMapPage.plan_key(pid, s)
	for i in 600:
		await tree.process_frame
		if PlanetMapPage.plan_texture(key) != null:
			break
	check(PlanetMapPage.plan_texture(key) != null, "its plan drawn")
	var names: Array = CosmosTown.places(str(s["kind"])).map(func(p): return p[0])
	for want in (["palace", "shrine", "store", "field", "vendor", "courier", "pilot"] if str(s["kind"]) == "city" else ["shrine", "store", "field"]):
		check(want in names, "its places: " + want)
	# The plan's points: on its buildings' ground (the palace in the middle, the field to the east).
	var r: Rect2 = PlanetMapPage.plan_rect(str(s["kind"]))
	for p in CosmosTown.places(str(s["kind"])):
		check(r.has_point(Vector2(p[2].x, p[2].z)), "on the plan: " + str(p[1]))
	var plan: Control = page._plan
	check(absf(plan._ppm / plan.fit_ppm() - 1.0) < 0.01, "all in: the whole town in view")
	plan.zoom(1.0 / 0.85)
	check(plan._ppm_t > plan.fit_ppm() * 1.1, "the plan's own zoom goes on in")
	await _wait(0.6)
	# Zoomed out past the whole town: the plan fades back into the globe.
	plan.zoom(0.85)
	plan.zoom(0.85)
	plan.zoom(0.85)
	check(not page.plan_shown(), "zoomed out past the whole town: the globe again")
	check(page.plan_blend() > 0.8, "  - the plan still over it at first (%.2f)" % page.plan_blend())
	await _wait(0.5)
	var b_out: float = page.plan_blend()
	check(b_out > 0.0 and b_out < 1.0, "  - partly faded (%.2f)" % b_out)
	for i in 12:
		v.zoom(1.0 / 0.85)
	await _wait(1.0)
	check(page.plan_blend() == 0.0 and not plan.visible, "zoomed further out: the globe alone")
	# Zooming in over it: the plan blends in a step at a time, laid where the town is.
	v.turn_to(td, PlanetMapPage.R * 2.0)
	await _wait(0.8)
	var blends: Array = []
	var aligned := true
	for i in 40:
		v.zoom(0.85)
		await _wait(0.2)
		blends.append(page.plan_blend())
		if plan.visible and not page.plan_shown():
			aligned = aligned and plan.centre_dir().angle_to(v.view_dir()) * shape.radius < 0.5 and absf(plan._ppm / v.ppm() - 1.0) < 0.01
		if page.plan_shown():
			break
	print("  (the plan's blend, a wheel notch at a time: %s)" % ", ".join(blends.map(func(b): return "%.2f" % b)))
	check(blends.any(func(b): return b > 0.1 and b < 0.9), "an intermediate zoom: the globe and the plan blended")
	var rising := true
	for i in range(1, blends.size()):
		rising = rising and blends[i] >= blends[i - 1] - 0.01
	check(rising, "  - more of the plan the nearer")
	check(aligned, "  - the plan where the town is on the globe, at its scale")
	check(page.plan_shown(), "zoomed all the way in: the plan alone")
	# A click (or Town plan): the same dive, eased.
	page.close_plan(true)
	await _wait(0.3)
	v.fit(true)
	await _wait(0.3)
	page.open_plan("town:0")
	await _wait(0.35)
	check(page.plan_blend() < 1.0, "a click: a dive onto it, not a cut (%.2f)" % page.plan_blend())
	await _wait(1.2)
	check(page.plan_shown(), "  - the plan, all in")
	page.close_plan()
	page.queue_free()
	Galaxy.new_game(false, true)


## The worlds' orbits never sweep through a station or an asteroid field, in
## any system, at any time (those in a world's orbit band co-orbit it); a
## moon keeps round its world.
func test_orbits_clear_of_stations_and_fields() -> void:
	var C: GDScript = load("res://scripts/world/space/cosmos.gd")
	var bad := 0
	var worst := ""
	for sid in Galaxy.systems:
		var recs: Array = C.planet_records(sid)
		if recs.is_empty():
			continue
		var radius := {}
		for r in recs:
			radius["planet:" + str(r["id"])] = float(r.get("size", 500.0)) * PlanetShape.SIZE_TO_R
		for k in 24:
			var t := k * 1777.0
			var pl: Dictionary = C.system_places(sid, t)
			for key in pl:
				if str(key).begins_with("planet:"):
					continue
				for pk in radius:
					var d: float = (pl[key] as Vector3).distance_to(pl[pk])
					if d < float(radius[pk]) * 1.1 + 1200.0:
						bad += 1
						worst = "%s %s by %s at t=%d: %.0f m" % [sid, key, pk, t, d]
	check(bad == 0, "nothing ever inside a world's path (%d; %s)" % [bad, worst])


func _wait(secs: float) -> void:
	var t_end := Time.get_ticks_msec() + int(secs * 1000.0)
	while Time.get_ticks_msec() < t_end:
		await tree.process_frame
