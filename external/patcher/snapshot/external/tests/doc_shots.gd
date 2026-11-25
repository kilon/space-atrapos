extends SceneTree
## Screenshots for the guide, the tutorial and the encyclopedia (data/docs/
## shots.json): each shot sets up a moment of the game and saves the screen,
## full size, as a PNG - tools/doc_shots.py then draws its infographic over it
## and saves it into data/docs/shots/. Run by that tool, in a window:
##   godot --path . -s tests/doc_shots.gd -- [shot ids...] --out=DIR
## (no ids: every shot).

const ALL := ["space_hud", "space_combat", "mining", "damage", "nav_beacon", "nav_report", "signal_site", "salvage",
	"station_market", "station_outfitting", "station_weapons", "station_shipyard", "station_missions", "station_reputation", "station_service",
	"computer_inventory", "computer_map", "probes", "computer_galaxy", "computer_tech", "computer_quest", "industry", "repair_bay", "surgery", "archive",
	"surface_walk", "field_inventory", "surface_map", "skill_book", "skills_fight", "space3d", "space3d_ground", "space3d_foot", "space3d_fight", "space3d_hangar"]

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
	if _any(["space_hud", "space_combat", "mining", "damage", "nav_beacon", "nav_report", "salvage"]):
		await _space()
	if _any(["signal_site"]):
		await _signal_site()
	if _any(["station_market", "station_outfitting", "station_weapons", "station_shipyard", "station_missions", "station_reputation", "station_service"]):
		await _station()
	if _any(["computer_inventory", "computer_map", "probes", "computer_galaxy", "computer_tech", "computer_quest", "industry", "repair_bay", "surgery", "archive"]):
		await _computer()
	if _any(["surface_walk", "field_inventory", "surface_map", "skill_book", "skills_fight"]):
		await _surface()
	if _any(["space3d", "space3d_ground", "space3d_foot", "space3d_fight", "space3d_hangar"]):
		await _space3d()
	await _set_scene(null)
	print("DOC SHOTS: " + ",".join(_done))
	quit()


func _any(ids: Array) -> bool:
	return ids.any(func(i): return i in _want)


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
	load("res://scripts/cosmos/cosmos.gd").arrive_from = ""
	await _set_scene(load("res://scenes/cosmos.tscn").instantiate())
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
	c.get_out()
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
		if x.kind == "pirate":
			c.target = x
			x.global_position = c.ship.global_position - c.ship.global_basis.z * 420.0 + c.ship.global_basis.x * 60.0
	c.ship.drive = {"fire": true}
	for i in 40:
		await process_frame
	await _snap("space3d_fight", 1.0)
	c.ship.drive = {}
	# Docked: the hangar.
	for x in c.npc_ships:
		x.queue_free()
	c.npc_ships.clear()
	c._pirate_cd = 9999.0
	c._place_ship()
	c.dry_run = true
	c.request_dock()
	while not (c.docked and c._dock.is_empty()):
		await process_frame
	c.get_out()
	c.cam.foot_zoom = 2.4
	await _snap("space3d_hangar", 2.5)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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


func _enter_space(system: String) -> Node:
	galaxy.current_system = system
	save.travelling = system != galaxy.HOME
	save.landed_planet = ""
	await _set_scene(load("res://main.tscn").instantiate())
	for i in 60:
		await process_frame
	save.travelling = false
	_scene.ship.invulnerable = true
	return _scene


# --- In space --------------------------------------------------------------

func _space() -> void:
	var main: Node = await _enter_space(galaxy.HOME)
	# The HUD: idle near the home station.
	var st: Node2D = _nearest_station(main)
	main.ship.global_position = st.global_position + Vector2(-700, 450)
	main.ship.stop()
	await _snap("space_hud", 2.5)
	# A fight: four raiders round you, you firing back.
	var foes := []
	for i in 4:
		foes.append(main.spawn_enemy(main.ship.global_position + Vector2.from_angle(i * TAU / 4.0 + 0.4) * 620.0))
	main.ship.set_attack_target(foes[0], true)
	await _snap("space_combat", 2.2)
	for e in foes:
		if is_instance_valid(e):
			e.queue_free()
	main.ship.set_attack_target(null)
	# Mining: the beam on the nearest rock.
	var rock: Node2D = null
	for r in main.asteroids.get_children():
		if rock == null or r.global_position.distance_to(main.ship.global_position) < rock.global_position.distance_to(main.ship.global_position):
			rock = r
	if rock:
		main.ship.global_position = rock.global_position + Vector2(0, 260)
		main.ship.rotation = 0.0
		main.ship.stop()
		main.ship.set_attack_target(rock)   # (no chase: it mines from where it stands)
		rock.scanned = true                  # (prospected: its veins - Mining)
		main.ship.mining_auto = true         # (cutting a vein, its heat kept in the band)
		await _snap("mining", 3.0)
		main.ship.mining_auto = false
		main.ship.set_attack_target(null)
	# Near death: afflictions under the bars, the failing screen and its cracks, sparks off the hull.
	if "damage" in _want:
		main.ship.global_position = st.global_position + Vector2(-900, 700)
		main.ship.stop()
		main.damage_screen._cracks._rng.seed = 11   # (the same cracks every time: the notes point at one)
		main.ship.hull = main.ship.max_hull * 0.07
		Parts.by_health(main.player_data.condition, "ship", 0.07)
		main.ship.apply_tech()
		main.hud.gauge.refresh()
		await _snap("damage", 3.0)
		Parts.clear_all(main.player_data.condition, "ship")
		main.ship.hull = main.ship.max_hull
		main.ship.apply_tech()
	# The navigation beacon by the star, not charted yet (and seen: on the radar).
	var nav: Node2D = get_first_node_in_group("nav_beacons")
	if nav and "nav_beacon" in _want:
		main.ship.global_position = nav.global_position + Vector2(-420, 260)
		main.ship.rotation = 0.6
		main.ship.stop()
		galaxy.reveal(nav.global_position)
		await _snap("nav_beacon", 2.0)
	# Its scan done: the system's navigation report.
	if nav and "nav_report" in _want:
		main.ship.global_position = nav.global_position + Vector2(-420, 260)
		main.ship.stop()
		main.chart_with_beacon(nav)
		await _snap("nav_report", 2.5)
		for p in get_nodes_in_group("nav_report_panel"):
			p.queue_free()
	# Salvage: a wreck cut apart with the Salvage Rig.
	if "salvage" in _want:
		main.player_data.add_equipment("salvage_rig")
		var at: Vector2 = main.ship.global_position + Vector2(380, -160)
		var w = load("res://scripts/wreck.gd").spawn(main, at, root.get_node("ProcArt").get_tex("ship_player"), Vector2.ONE, 0.6, {"kind": "ship", "title": "Sea Raider Ember-class Fighter"})
		main._start_salvage(w)
		await _snap("salvage", 2.5)


func _signal_site() -> void:
	var main: Node = await _enter_space(galaxy.HOME)
	var sig := {"id": "doc:distress", "kind": "stranded", "pos": [5000.0, 0.0], "located": true, "done": false, "seed": 777, "level": "normal"}
	var b: Node2D = load("res://scripts/signal_beacon.gd").new()
	b.sig = sig
	main.add_child(b)
	main.enter_site(b)
	await _snap("signal_site", 3.0)


func _nearest_station(main: Node) -> Node2D:
	var best: Node2D = null
	for s in get_nodes_in_group("stations"):
		if best == null or s.global_position.distance_to(main.ship.global_position) < best.global_position.distance_to(main.ship.global_position):
			best = s
	return best


# --- A station -------------------------------------------------------------

func _station() -> void:
	var main: Node = await _enter_space(galaxy.HOME)
	main.player_data.credits = 25000
	var st: Node2D = _nearest_station(main)
	main.station_menu.open(st)
	for i in 20:
		await process_frame
	var sm = main.station_menu
	var mp: Script = load("res://scripts/pages/market_page.gd")   # (by path: a class name here compiles the game before its autoloads)
	mp.category = 0
	mp.selected = "food"
	sm.show_tab(sm.TABS.find("MARKET"))
	await _snap("station_market")
	sm._outfit_tab = 3
	sm._quality = 2
	sm._outfit_sel = "mod:shield_generator"
	sm.show_tab(sm.TABS.find("OUTFITTING"))
	await _snap("station_outfitting")
	sm._outfit_tab = 1
	sm._wsize = 0
	sm._outfit_sel = "buy:wpn:plasma_cannon:0"
	sm.show_tab(sm.TABS.find("OUTFITTING"))
	await _snap("station_weapons")
	sm._yard_tab = -1
	sm.show_tab(sm.TABS.find("SHIPYARD"))
	await _snap("station_shipyard")
	sm.show_tab(sm.TABS.find("MISSIONS"))
	await _snap("station_missions")
	sm.show_tab(sm.TABS.find("REPUTATION"))
	await _snap("station_reputation")
	# The repair service: the technicians' evaluation of a battered ship and automaton.
	if "station_service" in _want:
		var pd = main.player_data
		main.ship.hull = main.ship.max_hull * 0.45
		Parts.by_health(pd.condition, "ship", 0.45)
		var rr := RandomNumberGenerator.new()
		rr.seed = 4
		Parts.add_fault(pd.condition, "automaton", "arms", "crack", 0, rr)
		sm._repair_page = 0
		sm.show_tab(0)
		sm._evaluate()
		await _snap("station_service")
		Parts.clear_all(pd.condition, "ship")
		Parts.clear_all(pd.condition, "automaton")
		main.ship.hull = main.ship.max_hull
	sm.close()


# --- The Ship Computer -----------------------------------------------------

func _computer() -> void:
	var main: Node = await _enter_space(galaxy.HOME)
	for sid in galaxy.stations:   # (every market known: the trade runs show)
		galaxy.visited[sid] = true
	galaxy.knowledge += 1
	var cm = main.ship_menu
	main._open_panel(cm, cm.INVENTORY_TAB)
	await _snap("computer_inventory")
	cm.show_tab(cm.MAP_TAB)
	await _snap("computer_map")
	# The probe scanner: probes out round the station, an analysis's signatures on the map.
	if "probes" in _want:
		main.player_data.add_equipment("probe_scanner")
		var mp = cm.page(cm.MAP_TAB)
		mp.show_probes(true)
		var c: Vector2 = main.ship.global_position + Vector2(2500, -1500)
		main.probes.launch_pattern(c, 4000.0)
		for p in main.probes.probes:
			p["at"] = p["pos"]
		main.probes._resolve()
		mp._view.center = c
		mp._view.scale_ = 0.045
		mp._view._fitted = true
		mp._probe_panel._reach = 4000.0
		mp._probe_panel.rebuild()
		await _snap("probes", 2.0)
		mp.show_probes(false)
	cm.show_tab(cm.GALAXY_TAB)
	var gp = cm._pages[cm.GALAXY_TAB]
	if not gp.trade:
		gp.toggle_trade()
	await _snap("computer_galaxy", 3.0)   # (the trade search runs a little a frame)
	cm.show_tab(cm.TECH_TAB)
	await _snap("computer_tech")
	# (the journal a few stages in: chapters, the objective, what happened)
	main.quest.load_save_data({"stage": 6, "lore": ["atropos", "phaistos_disc", "minoans"]})
	cm.show_tab(cm.QUEST_TAB)
	await _snap("computer_quest")
	# Industry: the fabricator at work, its components page.
	if "industry" in _want:
		var pdi = main.player_data
		pdi.add_equipment("refinery")
		pdi.add_equipment("fabricator")
		for k in {"frag:iron_ore": 24, "iron_ore": 14, "copper_ore": 9, "silver_ore": 3, "obsidian": 3, "titanium_ore": 6, "tin_ore": 3, "cobalt": 4}.keys():
			pdi.add_item(k, {"frag:iron_ore": 24, "iron_ore": 14, "copper_ore": 9, "silver_ore": 3, "obsidian": 3, "titanium_ore": 6, "tin_ore": 3, "cobalt": 4}[k])
		var ind: Script = load("res://scripts/industry.gd")   # (by path: a class name here compiles the game before its autoloads)
		ind.order(pdi, "refine", "frag:iron_ore", 12)
		ind.order(pdi, "fab", "circuit_boards", 2)
		cm.show_tab(cm.INDUSTRY_TAB)
		var ip = cm.page(cm.INDUSTRY_TAB)
		ip._page = 1
		ip._cat = 1
		ip.refresh()
		await _snap("industry", 2.0)
	# The Repair Bay mid-operation: the engines open, their faults found, a crack half welded.
	var pd = main.player_data
	for k in [["engines", "crack", 1], ["engines", "leak", 0], ["engines", "wreck", 4], ["sensors", "drift", 2], ["thrusters", "burn", 3], ["plating", "crack", 0]]:
		var r := RandomNumberGenerator.new()
		r.seed = 11 + k[2]
		Parts.add_fault(pd.condition, "ship", k[0], k[1], k[2], r)
	for f in Parts.part(pd.condition, "ship", "plating")["faults"]:
		f["found"] = true
	pd.add_item("spare_cell", 1)
	pd.add_item("spare_servo", 2)
	pd.add_item("spare_conduit", 1)
	main.ship.apply_tech()
	cm.show_tab(cm.REPAIR_TAB)
	var bay = cm._pages[cm.REPAIR_TAB]
	bay.pick_part("engines")
	var o: Dictionary = bay.op()
	o["bolts"].fill(false)
	o["open"] = true
	o["lift"] = 1.0
	o["heat"] = 38.0
	for f in bay.faults():
		f["found"] = true
	bay.set_tool("welder")
	bay._fill()
	var t = bay._table
	for f in bay.faults():
		if f["kind"] == "crack":
			var st: Dictionary = t.fstate(f)
			for i in st["done"].size() / 2:
				st["done"][i] = true
			var bits: Array = t.crack_bits(f)
			t._mouse = (bits[bits.size() / 2][0] + bits[bits.size() / 2][1]) * 0.5
	await _snap("repair_bay", 1.0)
	# The automaton on the table: its arm - a tear, and three incisions open down to the deeper layers.
	var cond: Dictionary = main.player_data.condition
	var r2 := RandomNumberGenerator.new()
	r2.seed = 5
	for spec in [["crack", 0], ["burn", 2], ["leak", 3], ["crack", 4]]:
		Parts.add_fault(cond, "automaton", "arms", spec[0], spec[1], r2)
	load("res://scripts/anatomy_art.gd").load_now()
	bay._pick_body("automaton")
	bay.pick_part("arms")
	for f in bay.faults():
		f["found"] = true
	var sg = bay._surgery
	for i in 4:
		await process_frame
	sg.opened()
	sg._view = sg._view_to
	for i in [2, 3, 4]:
		var cut: Dictionary = sg.cut_of(i)
		cut["done"].fill(true)
		cut["open"] = true
		cut["gape"] = 1.0
	bay.set_layer("muscles")
	bay.set_tool("clamp")
	bay._fill()
	sg._mouse = sg.site(3) + Vector2(70, -46)
	await _snap("surgery", 1.0)
	cm.close()
	# The Archive, as a window (F1, a Guide button): the guide at the Repair Bay.
	for i in 30:
		await process_frame
	var ar: Control = load("res://scripts/archive.gd").open(main, "guide", "guide/repair-bay")   # (loaded now: it needs the autoloads)
	await _snap("archive", 1.0)
	ar.get_parent().get_parent().get_parent().close()


# --- A planet --------------------------------------------------------------

func _surface() -> void:
	save.landed_planet = "thalassa"
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	await _set_scene(s)
	while not s.is_built:
		await process_frame
	for i in 60:
		await process_frame
	s.pilot.hp = s.pilot.max_hp
	await _snap("surface_walk", 2.5)
	s.field_menu.open(s.field_menu.INVENTORY_TAB)
	await _snap("field_inventory")
	s.field_menu.close()
	s.field_menu.open(s.field_menu.MAP_TAB)
	await _snap("surface_map", 2.0)
	s.field_menu.close()
	if not _any(["skill_book", "skills_fight"]):
		return
	# The Spell Book: a few levels in, some skills learned and raised.
	var sk: GDScript = load("res://scripts/skills.gd")   # (loaded now: it needs the autoloads)
	var st: Dictionary = sk.state(s.state["player"])
	st["level"] = 6
	st["xp"] = 210
	st["points"] = 2
	st["ranks"] = {"pygmachia": 3, "pankration": 2, "guard": 1, "leap": 2, "phlox": 3, "lance": 1, "keraunos": 1}
	var bar: Array = s.foot_toolbar()
	for i in 6:
		bar[3 + i] = ["skill:pygmachia", "skill:leap", "skill:phlox", "skill:pankration", "skill:lance", "skill:keraunos"][i]
	s.field_menu.open(s.field_menu.SKILLS_TAB)
	for i in 10:
		await process_frame
	s.field_menu._pages[s.field_menu.SKILLS_TAB]._describe("keraunos")
	await _snap("skill_book", 1.2)
	s.field_menu.close()
	for i in 40:
		await process_frame
	# A fight on foot: the dome up, the eidola out, the thunderbolt coming down on a pirate.
	for id in sk.SKILLS:
		st["ranks"][id] = 5
	s.pilot.max_hp = 9000.0
	s.pilot.hp = 9000.0
	var at: Vector2 = s.pilot.position
	var foes := []
	for k in 3:
		var where: Vector2 = at + Vector2(250 + k * 70, -40 + k * 75)
		var pz: Node2D = s._spawn_npc(where, 1 + k, where, "pirate")
		pz.max_hp = 9000.0
		pz.hp = 8000.0
		foes.append(pz)
	s.pilot.stamina = 100.0
	s.use_skill("aegis")
	for i in 55:
		await process_frame
	s.use_skill("eidola")
	for i in 110:
		await process_frame
	s._tool_cd.clear()
	s.use_skill("keraunos", foes[1].position)
	await _snap("skills_fight", 0.5)
