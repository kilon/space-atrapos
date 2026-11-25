extends TestCase
## Fog of war (FogOfWar): on the planets' minimap and map (PlanetSurface.fog)
## and the system map (Galaxy.fog) - revealed round you, saved, and what
## lies in the dark kept off the maps.


func test_fog_grid() -> void:
	var f := FogOfWar.new(20, 20, Vector2(-100, -100), 10.0)
	check(not f.explored(Vector2.ZERO), "nothing seen at first")
	check(f.reveal(Vector2.ZERO, 50.0), "revealing shows something new")
	check(f.explored(Vector2.ZERO) and f.explored(Vector2(25, 0)), "seen round the point")
	check(not f.explored(Vector2(80, 80)), "not far away")
	check(not f.reveal(Vector2.ZERO, 50.0), "the same again: nothing new")
	check_eq(f.seen_at(Vector2(5000, 0)), 0, "outside the grid: unseen")
	var tex := f.texture()
	check(tex != null and tex.get_size() == Vector2(80, 80), "a smoothed texture (4 texels a cell)")
	var g := FogOfWar.new(20, 20, Vector2(-100, -100), 10.0)
	g.load_from(f.save())
	check_eq(g.data, f.data, "saved and loaded")


func test_surface_fog() -> void:
	SaveGame.space_state = {}
	SaveGame.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	await tree.create_timer(0.15).timeout   # (revealed a moment after the world shows: not in its first, long frame)
	check(s.fog != null and s.explored_at(s.pilot.position), "where you stand is explored")
	var far: Vector2 = s.pilot.position + Vector2(9000, 4000)
	check(not s.explored_at(far), "far away isn't")
	check(s.fog.explored_share() < 0.05, "most of the planet is dark (%.3f)" % s.fog.explored_share())
	s.reveal_around(far)
	check(s.explored_at(far), "walking there reveals it")
	var st: Dictionary = s.get_save_data()
	check(str(st["planets"]["thalassa"].get("explored", "")) != "", "kept in the state (saved, and taken back to space)")
	var copy := FogOfWar.new(s.fog.cols, s.fog.rows, Vector2.ZERO, float(s.FOG_CELL))
	copy.load_from(st["planets"]["thalassa"]["explored"])
	check_eq(copy.data, s.fog.data, "and it loads back")
	s.queue_free()
	await tree.process_frame


func test_system_fog() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false
	var m: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(m)
	for i in 10:
		await tree.process_frame
	check(Galaxy.explored_at(m.ship.global_position), "your ship's surroundings are swept")
	var hidden := tree.get_nodes_in_group("stations").filter(func(st): return not Galaxy.explored_at(st.global_position))
	check(not hidden.is_empty(), "some stations are still in the dark")
	var view = load("res://scripts/pages/map_page.gd").MapView.new()
	view.page = load("res://scripts/pages/map_page.gd").new()
	view.ship = m.ship
	m.add_child(view)
	view.size = Vector2(1200, 600)
	view.rebuild()
	view.fit()
	var st: Node2D = hidden[0]
	view.center = st.global_position
	check(view._pick(view.to_screen(st.global_position)).is_empty(), "a station in the dark can't be picked on the map")
	Galaxy.reveal(st.global_position)
	check(view._pick(view.to_screen(st.global_position)).get("name", "") == st.station_name, "once swept, it can")
	# Saved with the galaxy; an old save (from before the fog) is all charted.
	var d: Dictionary = Galaxy.get_save_data()
	check(d.has("explored") and d["explored"].has(Galaxy.current_system), "the fog is saved")
	Galaxy.load_save_data(JSON.parse_string(JSON.stringify(d)))
	check(Galaxy.explored_at(st.global_position), "and loaded")
	d.erase("explored")
	Galaxy.load_save_data(d)
	check(Galaxy.explored_at(Vector2(9000, -9000)), "an old save: everything charted")
	view.page.free()
	m.queue_free()
	for i in 3:
		await tree.process_frame
	Galaxy.new_game(false)


## The navigation beacon by the star: scanning it (right-click) charts the system for good -
## no fog, every station, planet, moon and gate on the maps (and seen).
func test_nav_beacon_report() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false
	var m: Node = load("res://main.tscn").instantiate()
	tree.root.add_child(m)
	for i in 10:
		await tree.process_frame
	var beacons := tree.get_nodes_in_group("nav_beacons")
	check_eq(beacons.size(), 1, "one navigation beacon in the system")
	if beacons.is_empty():
		m.queue_free()
		return
	var b: NavBeacon = beacons[0]
	var star: Node2D = tree.get_first_node_in_group("star")
	var d: float = b.global_position.distance_to(star.global_position)
	check(d > star.radius and d < star.radius + 1000.0, "next to the star (%.0f from it)" % d)
	var dark := func(n): return not Galaxy.explored_at(n.global_position)
	check(tree.get_nodes_in_group("stations").any(dark) or tree.get_nodes_in_group("gates").any(dark), "some of the system still in the dark")
	check(not b.charted(), "not charted yet")
	# A left click on it: just flies there; a right-click scans it.
	m.ship.global_position = b.global_position + Vector2(0, 500)
	await tree.process_frame
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = m.get_viewport().get_canvas_transform() * b.global_position
	m._unhandled_input(click)
	check(not b.charted(), "a left click doesn't chart it")
	click.button_index = MOUSE_BUTTON_RIGHT
	m._unhandled_input(click)
	check(not b.charted() and b.scan == 0.0, "right-clicked: the scan starts - not charted yet")
	m._update_beacon_scan(NavBeacon.SCAN_TIME * 0.5)
	check(is_equal_approx(b.scan, 0.5) and not b.charted(), "half way: half scanned")
	# Out of range: the scan is lost.
	m.ship.global_position = b.global_position + Vector2(NavBeacon.SCAN_RANGE * 2.0, 0)
	m._update_beacon_scan(0.1)
	check(b.scan < 0.0 and not b.charted(), "flew out of range: the scan lost")
	m.ship.global_position = b.global_position + Vector2(0, 500)
	m._unhandled_input(click)
	m._update_beacon_scan(NavBeacon.SCAN_TIME - 0.1)
	check(not b.charted(), "not before SCAN_TIME (%.0f s)" % NavBeacon.SCAN_TIME)
	m._update_beacon_scan(0.2)
	check(b.charted() and Galaxy.charted.has(Galaxy.current_system), "scanned for SCAN_TIME: the beacon scanned")
	# Its navigation report: what's in the system - the fog stays.
	var sys_id: String = Galaxy.current_system
	check(Galaxy.fog().explored_share() < 0.99, "the fog stays (%.2f explored)" % Galaxy.fog().explored_share())
	var r: Dictionary = Galaxy.reports.get(sys_id, {})
	check(not r.is_empty(), "a navigation report made")
	check_eq(r.get("stations", []).size(), tree.get_nodes_in_group("stations").size(), "it lists every station")
	check_eq(r.get("gates", []).size(), tree.get_nodes_in_group("gates").size(), "every gate")
	check(r.get("bodies", []).size() > 0, "the planets and moons (%d)" % r.get("bodies", []).size())
	check(r.has("hostile") and r.has("friendly") and r.has("roles"), "the ships about, hostile and friendly, by trade")
	check(not tree.get_nodes_in_group("nav_report_panel").is_empty(), "shown on screen")
	var rid := NavReports.id_for(sys_id)
	check_eq(m.player_data.count(rid), 1, "a copy in the hold")
	check(Items.info(rid)["name"].contains(Galaxy.SYSTEMS[sys_id]["name"]), "named for its system: " + Items.info(rid)["name"])
	for p in tree.get_nodes_in_group("nav_report_panel"):
		p.queue_free()
	# One a visit: scanned again - the report shown, no second copy; after a jump away and back, another.
	m.chart_with_beacon(b)
	check_eq(m.player_data.count(rid), 1, "scanned again this visit: no second copy")
	Galaxy.jumps += 2
	m.chart_with_beacon(b)
	check_eq(m.player_data.count(rid), 2, "back after leaving: another copy")
	# Priced by distance: nothing in its own system, more the further away.
	var n1: String = Galaxy.neighbors(sys_id)[0]
	var far := n1
	for s2 in Galaxy.SYSTEMS:
		if NavReports.jumps(sys_id, s2) > NavReports.jumps(sys_id, far):
			far = s2
	check_eq(NavReports.price(sys_id, sys_id), 0, "worthless in its own system")
	check(NavReports.price(sys_id, n1) > 0, "sells next door (%d dr)" % NavReports.price(sys_id, n1))
	check(NavReports.price(sys_id, far) > NavReports.price(sys_id, n1), "more the further (%d jumps: %d dr)" % [NavReports.jumps(sys_id, far), NavReports.price(sys_id, far)])
	# For good: saved and loaded; another system not scanned.
	var s: Dictionary = JSON.parse_string(JSON.stringify(Galaxy.get_save_data()))
	Galaxy.charted = {}
	Galaxy.reports = {}
	Galaxy.load_save_data(s)
	check(Galaxy.charted.has(sys_id) and Galaxy.reports.has(sys_id), "scanned and its report kept after loading")
	check(not Galaxy.charted.has(Galaxy.neighbors(sys_id)[0]), "only this system")
	m.queue_free()
	for i in 3:
		await tree.process_frame
	Galaxy.new_game(false)
