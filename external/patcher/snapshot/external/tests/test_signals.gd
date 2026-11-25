extends TestCase
## Signal sources (SignalSites): located by a system scan (with paths to
## them while the scan lasts), entered from their beacons into a pocket of
## empty space, each kind's encounter playing out and finishing, leaving back
## beside the beacon, and saving while inside.

var _main: Node


func setup() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false


func teardown() -> void:
	if is_instance_valid(_main):
		_main.queue_free()
	await tree.process_frame
	tree.paused = false
	Galaxy.new_game(false)
	NeonTheme.set_empire("")


func _game() -> Node:
	if is_instance_valid(_main):
		_main.queue_free()
		await tree.process_frame
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	for i in 40:
		await tree.process_frame
	return _main


func _signal(kind: String) -> Dictionary:
	for sg in Galaxy.signals_in():
		if sg["kind"] == kind:
			return sg
	var sg: Dictionary = Galaxy.signals_in()[0].duplicate()
	sg["id"] = "test:" + kind
	sg["kind"] = kind
	Galaxy.signals_in().append(sg)
	return sg


func _enter_kind(main: Node, kind: String) -> SignalSite:
	var sg := _signal(kind)
	sg["located"] = true
	sg["done"] = false
	main.refresh_beacons()
	var b: SignalBeacon = main._beacons[sg["id"]]
	main.ship.global_position = b.global_position + Vector2(0, 200)
	main.request_site(b)
	await tree.process_frame
	return main.site


func test_signals_generated() -> void:
	var a := SignalSites.generate("atrapos", 0)
	var b := SignalSites.generate("atrapos", 0)
	check(a.size() >= 12 and a.size() <= 36, "12-36 signals a system (%d)" % a.size())
	check_eq(a.map(func(s): return [s["kind"], s["pos"]]), b.map(func(s): return [s["kind"], s["pos"]]), "the same for the same system and epoch")
	var kinds := {}
	for s in a:
		kinds[s["kind"]] = true
		check(SignalSites.pos(s).length() >= 4000.0 and SignalSites.pos(s).length() <= 16000.0, "out in the system")
		check(not s["located"] and not s["done"], "not located yet")
	check_eq(kinds.size(), SignalSites.signal_kinds().size(), "every kind there")
	var close := 0
	for i in a.size():
		for j in range(i + 1, a.size()):
			if SignalSites.pos(a[i]).distance_to(SignalSites.pos(a[j])) < SignalSites.APART:
				close += 1
	check_eq(close, 0, "no two on top of each other")
	var sizes := {}
	for sys in ["atrapos", "knossos", "delos", "a", "b", "c", "d", "e", "f", "g"]:
		for ep in 4:
			var n := SignalSites.generate(sys, ep).size()
			sizes[n] = true
			check(n >= 12 and n <= 36, "%s/%d: %d signals" % [sys, ep, n])
	check(sizes.size() > 5, "how many varies (%d different counts)" % sizes.size())
	var seen := {}
	for ep in 12:
		for s in SignalSites.generate("atrapos", ep):
			seen[s["kind"]] = true
	check_eq(seen.size(), SignalSites.signal_kinds().size(), "every kind turns up")
	# A new epoch: fresh signals, the located unfinished ones kept.
	Galaxy.new_game(false)
	var first: Array = Galaxy.signals_in()
	first[0]["located"] = true
	Galaxy.time += SignalSites.EPOCH
	var next: Array = Galaxy.signals_in()
	check(next.any(func(s): return s["id"] == first[0]["id"]), "a located signal stays into the next epoch")
	check(next.size() > 1 and next.any(func(s): return s["id"] != first[0]["id"]), "with new ones")
	var saved := Galaxy.get_save_data()
	Galaxy.load_save_data(saved)
	check_eq(Galaxy.signals_in().size(), next.size(), "saved and loaded")


func test_scan_locates_signals() -> void:
	var main: Node = await _game()
	var ps: ProbeScanner = main.probes
	check(tree.get_nodes_in_group("signal_beacons").filter(func(b): return b.sig.get("kind", "") != "ring").all(func(b): return not b.active()), "no beacons before the probes find them")
	main.player_data.add_equipment("probe_scanner")
	var sg: Dictionary = Galaxy.signals_in().filter(func(x): return not x["done"])[0]
	var at := SignalSites.pos(sg)
	# A wide sweep: something's there, but not where.
	ps.launch_pattern(at + Vector2(3000, 2000), 16000.0)
	for p in ps.probes:
		p["at"] = p["pos"]
	ps.analyze()
	ps._process(ProbeScanner.ANALYZE_TIME + 0.1)
	var wide: Array = ps.results.filter(func(r): return r.get("sig") == sg)
	check(wide.size() == 1 and float(wide[0]["strength"]) < 1.0, "a wide sweep reads it, not located (%s)" % str(wide.map(func(r): return r["strength"])))
	check(not sg["located"], "so no beacon yet")
	# Probes drawn tight round it: located.
	ps.launch_pattern(at, 1000.0)
	for p in ps.probes:
		p["at"] = p["pos"]
	ps.analyze()
	ps._process(ProbeScanner.ANALYZE_TIME + 0.1)
	var tight: Array = ps.results.filter(func(r): return r.get("sig") == sg)
	check(tight.size() == 1 and float(tight[0]["strength"]) >= 1.0, "tight round it: 100%")
	check(sg["located"], "located: its beacon appears")
	var active := tree.get_nodes_in_group("signal_beacons").filter(func(b): return b.active() and b.sig.get("kind", "") != "ring")
	check(active.any(func(b): return b.sig == sg), "its beacon is active")
	# An ENTER button over a beacon on screen.
	var b: SignalBeacon = active[0]
	main.ship.global_position = b.global_position + Vector2(0, 300)
	main.get_node("Ship/Camera2D").reset_smoothing()
	for i in 4:
		await tree.process_frame
	var ui: Node = null
	for c in main.hud.get_children():
		if c.get("_enter") != null:
			ui = c
	check(ui != null and ui._enter.has(b) and ui._enter[b].visible, "an ENTER button over its beacon")
	check(ui._enter[b].text.contains(b.title().to_upper()), "naming it")


func test_enter_and_leave() -> void:
	var main: Node = await _game()
	var site: SignalSite = await _enter_kind(main, "wreck")
	check(site != null, "ENTER near the beacon drops you in")
	var back: Vector2 = site.return_point
	check(main.ship.global_position.distance_to(SignalSite.ORIGIN) < 2000.0, "you're in the site's pocket of space")
	check(tree.get_nodes_in_group("stations").all(func(st): return st.global_position.distance_to(main.ship.global_position) > 100000.0), "no stations out here")
	# Saving in the site saves you at the beacon (the site's ships aren't saved).
	var d: Dictionary = main.get_save_data()
	check(Vector2(d["ship"]["position"][0], d["ship"]["position"][1]).distance_to(back) < 1.0, "saved: you're back beside the beacon")
	site.leave()
	await tree.process_frame
	check(main.site == null and main.ship.global_position.distance_to(back) < 1.0, "leaving: back beside the beacon")
	check(not tree.get_nodes_in_group("pickups").any(func(p): return p.global_position.distance_to(SignalSite.ORIGIN) < 20000.0), "the site's loot is gone")
	# From afar: you fly there first, then drop in.
	var sg := _signal("monster")
	sg["located"] = true
	main.refresh_beacons()
	var b: SignalBeacon = main._beacons[sg["id"]]
	main.ship.global_position = b.global_position + Vector2(2500, 0)
	main.request_site(b)
	check(main.site == null and main._site_on_arrival == b, "far away: you fly to it first")
	main.ship.global_position = b.global_position + Vector2(100, 0)
	await tree.process_frame
	check(main.site != null and main.site.kind == "monster", "and drop in on arrival")
	main.site.leave()
	await tree.process_frame
	# Flying out of the site leaves it.
	site = await _enter_kind(main, "wreck")
	main.ship.global_position = SignalSite.ORIGIN + Vector2(SignalSite.BOUNDS + 100.0, 0)
	await tree.process_frame
	await tree.process_frame
	check(main.site == null, "flying out of the site leaves it")


func test_wreck_and_monster() -> void:
	var main: Node = await _game()
	var site: SignalSite = await _enter_kind(main, "wreck")
	check(site._loot.size() >= 10, "salvage drifting round the wreck (%d)" % site._loot.size())
	check(site._loot.all(func(p): return p.permanent), "and it doesn't expire")
	for p in site._loot:
		p.queue_free()
	await tree.process_frame
	await tree.process_frame
	check(site.done and site.sig["done"], "all collected: done")
	site.leave()
	await tree.process_frame
	site = await _enter_kind(main, "monster")
	var m: Node2D = site._monster
	var look: Node = m.body.get_node_or_null("Monster") if m else null
	check((look is SeaWitch and m.display_name == "Skylla") or (look is CerberusBeast and m.display_name == "Cerberus") or (look is CetusBeast and m.display_name == "Cetus") or (look is EchidnaBeast and m.display_name == "Echidna") or (look is HydraBeast and m.display_name == "The Hydra") or (look is ChimeraBeast and m.display_name == "The Chimera") or (look is CharybdisBeast and m.display_name == "Charybdis"),
		"a creature from its art: %s" % (m.display_name if m else "none"))
	check(m.hull >= 900.0, "a big one")
	# Its attacks: patterns of slow energy orbs, telegraphed, dodgeable.
	var mon: SpaceMonster = m.body.get_node("Monster")
	main.ship.global_position = m.global_position + Vector2(0, 600)
	main.ship.hull = 99999.0
	main.ship.max_hull = 99999.0
	var seen := {}
	for i in 600:
		m._target = main.ship
		mon._process(1.0 / 60.0)
		if mon.pattern != "":
			seen[mon.pattern] = true
		await tree.process_frame
	check(mon.orbs_fired > 60, "it fires orbs (%d in 10 s)" % mon.orbs_fired)
	check(seen.size() >= 2 and not seen.keys().any(func(k): return k in SpaceMonster.PATTERNS), "in its own patterns (%s)" % ", ".join(seen.keys()))
	var orbs := tree.get_nodes_in_group("monster_orbs")
	check(not orbs.is_empty() and orbs.all(func(o): return o.velocity.length() < main.ship.max_speed * 0.6), "slower than your ship: dodgeable")
	check(main.enemies.get_children().all(func(c): return not c is SpaceMonster.Orb), "orbs aren't among the ships")
	check(main._enemy_at(orbs[0].global_position) == null or main._enemy_at(orbs[0].global_position) != orbs[0], "and clicking where they fly works")
	# A ring of 18 at 300 out leaves gaps wider than your hitbox.
	var gap := TAU * 300.0 / 18.0 - 2.0 * 11.0
	check(gap > 2.0 * main.ship.hit_radius * SpaceMonster.Orb.HITBOX + 20.0, "the ring's gaps (%d px) let you through" % int(gap))
	main.ship.shields = main.ship.max_shields
	var sh: float = main.ship.shields
	mon._orb(Vector2.ZERO, SpaceMonster.ORB_COLOR).global_position = main.ship.global_position
	await tree.process_frame
	await tree.process_frame
	check(main.ship.shields < sh, "an orb that touches you hurts")
	m.take_damage(99999.0, m.global_position, main.ship)
	await tree.process_frame
	check(not site.done, "dying: it shakes and bursts first (SpaceMonster.death_throes)")
	var t0 := Time.get_ticks_msec()
	while not site.done and Time.get_ticks_msec() - t0 < 6000:
		await tree.process_frame
	check(site.done, "killed: done, after the big explosion")
	var drops := tree.get_nodes_in_group("pickups").filter(func(p): return p.global_position.distance_to(SignalSite.ORIGIN) < 3000.0)
	check(drops.any(func(p): return p.item_id == "alien_alloy") and drops.any(func(p): return p.item_id == "data_core"), "it drops alien alloy and data cores")


func test_stranded_and_under_attack() -> void:
	var main: Node = await _game()
	var site: SignalSite = await _enter_kind(main, "stranded")
	site._ambush = false
	var v: Node2D = site._victim
	check(v != null and v.is_neutral() and v.display_name.begins_with("Stranded"), "a stranded ship")
	main.ship.global_position = v.global_position + Vector2(0, 200)
	await tree.process_frame
	check(site._action.visible and site._action.disabled, "close up: the transfer button, disabled with no fuel")
	main.player_data.add_item("fuel", 5)
	await tree.process_frame
	check(not site._action.disabled, "with 5 fuel: you can transfer it")
	var cr: int = main.player_data.credits
	site._help_stranded()
	check(site.done and main.player_data.count("fuel") == 0 and main.player_data.credits > cr, "refuelled: paid, done")
	site.leave()
	await tree.process_frame
	site = await _enter_kind(main, "under_attack")
	check(site._pirates.size() >= 3 and is_instance_valid(site._victim), "a freighter and its attackers")
	cr = main.player_data.credits
	for p in site._pirates:
		p.take_damage(99999.0, p.global_position, main.ship)
	for i in 4:
		await tree.process_frame
	check(site.done, "the pirates dead: done")
	check(main.player_data.credits > cr, "the freighter paid you")


func test_anomaly_scan() -> void:
	var main: Node = await _game()
	var site: SignalSite = await _enter_kind(main, "anomaly")
	check_eq(site.scan_points.size(), 4, "four nodes to scan")
	var sc: ShipScanner = main.scanner
	var node: Node2D = site.scan_points[0]
	main.ship.global_position = node.global_position + Vector2(0, 2000)
	check(not sc.scan_rock(node), "too far: no scan")
	main.ship.global_position = node.global_position + Vector2(0, 300)
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_RIGHT
	e.pressed = true
	e.position = main.get_canvas_transform() * node.global_position
	main._unhandled_input(e)
	check(sc._rock == node, "right-click a node close up: scanning it")
	await tree.create_timer(sc.ROCK_TIME + 0.3).timeout
	check(node.scanned, "scanned")
	for s in site.scan_points:
		s.scanned = true
	await tree.process_frame
	await tree.process_frame
	check(site.done, "all four: done")
	check(tree.get_nodes_in_group("pickups").any(func(p): return p.item_id == "research_data"), "research data")
	check(Items.is_cargo("research_data"), "(cargo you can sell)")


func test_deathtrap() -> void:
	var main: Node = await _game()
	var site: SignalSite = await _enter_kind(main, "deathtrap")
	var ship: Node2D = main.ship
	check(site.hazards.size() > 40, "a field of hazards (%d)" % site.hazards.size())
	check(ship.global_position.distance_to(site.path[0]) < 1.0, "you start at the entry")
	# The safe line is clear of every hazard, all the way.
	var clear := true
	for i in site.path.size() - 1:
		for k in 20:
			var p: Vector2 = site.path[i].lerp(site.path[i + 1], k / 20.0)
			for h in site.hazards:
				if p.distance_to(h["pos"]) < float(h["r"]) * 1.1 + 60.0:
					clear = false
	check(clear, "a safe line runs through it")
	# Inside a hazard: shields drain, then the hull burns.
	var h: Dictionary = site.hazards[0]
	ship.global_position = h["pos"]
	var sh: float = ship.shields
	for i in 10:
		await tree.process_frame
	check(site.in_hazard and ship.shields < sh, "inside a hazard: shields draining")
	ship.shields = 0.0
	var hull: float = ship.hull
	for i in 10:
		await tree.process_frame
	check(ship.hull < hull, "then the hull burns")
	ship.hull = ship.max_hull
	ship.shields = ship.max_shields
	# The exit: the prize.
	ship.global_position = site.exit_point
	await tree.process_frame
	await tree.process_frame
	check(site.done, "the exit reached: done")
	check(tree.get_nodes_in_group("pickups").any(func(p): return p.item_id == "data_core" and p.global_position.distance_to(site.exit_point) < 300.0), "the prize at the exit")
	site.leave()
	await tree.process_frame
	# Flying out of its sides leaves it, empty-handed.
	site = await _enter_kind(main, "deathtrap")
	var sg: Dictionary = site.sig
	var dir: Vector2 = (site.exit_point - site.path[0]).normalized()
	ship.global_position = site.path[0] + dir * 1000.0 + dir.orthogonal() * (SignalSite.FIELD_HALF_WIDTH + 400.0)
	await tree.process_frame
	await tree.process_frame
	check(main.site == null and not sg["done"], "out of its sides: left, not done")


## Signals are seen (radar, system map) and their paths reach only within
## ShipScanner.signal_range() - a third of the system across.
func test_signal_range() -> void:
	var main: Node = await _game()
	var reach: float = ShipScanner.signal_range(tree)
	var far := 0.0
	for g in ["gates", "stations", "planet_bodies"]:
		for n in tree.get_nodes_in_group(g):
			if n.global_position.distance_to(SignalSite.ORIGIN) > SignalSite.BOUNDS * 2.0:
				far = maxf(far, n.global_position.length())
	check(absf(reach - far * 2.0 / 3.0) < 1.0, "a third of the system across (%.0f)" % reach)
	var me: Vector2 = main.ship.global_position
	check(ShipScanner.signal_visible(tree, me + Vector2(reach * 0.9, 0), me), "inside the range: seen")
	check(not ShipScanner.signal_visible(tree, me + Vector2(reach * 1.1, 0), me), "beyond it: not on the radar or the map")


## Both creatures of the monster signals: picked by the signal, each rigged from its art.
func test_signal_creatures() -> void:
	var main: Node = await _game()
	var kinds := {}
	for c in SignalSite.CREATURES:
		kinds[c[0]] = true
		var e: Node2D = main.spawn_ship(main.ship.global_position + Vector2(0, -900), c[0])
		for i in 3:
			await tree.process_frame
		var look: Node = e.body.get_node_or_null("Monster")
		check(look != null and e.display_name == c[1], "%s spawns as a creature" % c[1])
		if look is CerberusBeast:
			check(look._joints.size() == 7, "Cerberus: tail, two heads, four legs rigged")
			var jaws := [look.jaw(0), look.jaw(1), look.jaw(2)]
			check(jaws[0].x < jaws[1].x and jaws[1].x < jaws[2].x, "three jaws, left to right")
			look._orb(Vector2(100, 0), SpaceMonster.ORB_COLOR)
			look._orb(Vector2(100, 0), SpaceMonster.ORB_COLOR)
			var orbs := tree.get_nodes_in_group("monster_orbs")
			check(orbs.size() >= 2 and orbs[-1].global_position.distance_to(orbs[-2].global_position) > 50.0, "fire from different jaws")
		if look is CetusBeast:
			check(look._joints.size() == 3, "Cetus: fins and tail rigged")
			check(look._side != null and not look._side.visible, "the side view waits for the breach")
		if look is EchidnaBeast:
			check(look._joints.size() == 3, "Echidna: arms and tail rigged")
			check(look._front != null and not look._front.visible, "the front view waits for her brood")
		if look is CharybdisBeast:
			# The whirlpool drags you toward its maw.
			main.ship.global_position = e.global_position + Vector2(0, 700)
			main.ship.velocity = Vector2.ZERO
			main.ship.stop()
			e._target = main.ship
			look.special = "whirlpool"
			look._sp = CharybdisBeast.WHIRL_WINDUP
			var d0: float = main.ship.global_position.distance_to(e.global_position)
			for i in 20:
				look._run_special(1.0 / 60.0)
			check(main.ship.global_position.distance_to(e.global_position) < d0 - 30.0, "Charybdis: its whirlpool drags you in")
			look.special = ""
		if look is ChimeraBeast:
			check(look._joints.size() == 6, "the Chimera: lion, goat, serpent and three legs rigged")
			var jaws := [look.jaw("lion"), look.jaw("goat"), look.jaw("serpent")]
			check(jaws[0].distance_to(jaws[1]) > 50.0 and jaws[1].distance_to(jaws[2]) > 50.0, "three heads, three jaws")
			check(look._front != null and not look._front.visible, "the front view waits for its rampage")
		if look is HydraBeast:
			check(look._joints.size() == 8 and look.heads().size() == 8, "the Hydra: eight heads")
			var jaws := {}
			for h in look.heads():
				jaws[Vector2i(look.jaw(h))] = true
			check(jaws.size() == 8, "each with its own jaws")
			e.hull = e.max_hull * 0.9
			for i in 3:
				await tree.process_frame
			check(look.heads().size() == 7 and look.heads_severed == 1, "a portion of its hull lost: a head is cut off")
			check(look.double_heads.size() == 1 and look.double_heads[0].body.get_node_or_null("Monster") is HydraHead, "and a double head grows in its place")
			var dh: Node2D = look.double_heads[0]
			check(is_equal_approx(dh.max_hull, e.max_hull * 0.1) and is_equal_approx(dh.hull, dh.max_hull), "with a tenth of the Hydra's hull")
			check(not dh.body.get_node("Monster").cinematic, "and a quick death, the camera left alone")
			var hp0: float = dh.hull
			dh.take_damage(500.0, dh.global_position, main.ship)
			check(dh.is_alive() and is_equal_approx(dh.hull, hp0), "it can't be hurt")
			check(not dh.is_in_group(&"enemies") and main._enemy_at(dh.global_position) != dh, "nor targeted (no shots find it, no click picks it)")
			check(main.hud._boss_bar.boss == null or main.hud._boss_bar.boss == e, "the health bar is only ever the Hydra's")
			for h in look.severed.keys():
				look.severed[h] = 0.01
			for i in 3:
				await tree.process_frame
			check(look.heads().size() == 8, "the cut head grows back")
			e.hull = 1.0
			for i in 40:
				await tree.process_frame
			check(look.double_heads.size() <= HydraBeast.MAX_DOUBLE and look.double_heads.size() > 1, "more of them, at most twelve (%d)" % look.double_heads.size())
			e.global_position += Vector2(900, 0)
			var t0 := Time.get_ticks_msec()
			while Time.get_ticks_msec() - t0 < 2500 and is_instance_valid(dh) and dh.global_position.distance_to(e.global_position) > 600.0:
				await tree.process_frame
			check(is_instance_valid(dh) and dh.global_position.distance_to(e.global_position) < 600.0, "they keep round the Hydra (%d away)" % (dh.global_position.distance_to(e.global_position) if is_instance_valid(dh) else -1))
			var heads: Array = look.double_heads.duplicate()
			e.take_damage(99999.0, e.global_position)
			for i in 5:
				await tree.process_frame
			check(heads.all(func(d): return not is_instance_valid(d) or not d.is_alive()), "and die with it")
			var cam: Camera2D = tree.root.get_viewport().get_camera_2d()
			var t1 := Time.get_ticks_msec()
			while is_instance_valid(e) and Time.get_ticks_msec() - t1 < 8000:
				await tree.process_frame
			check(cam == null or (not cam.top_level and cam.position.length() < 1.0), "the camera back on your ship after it dies")
		if is_instance_valid(e):
			e.queue_free()
	check(kinds.has("skylla") and kinds.has("cerberus") and kinds.has("cetus") and kinds.has("echidna") and kinds.has("hydra") and kinds.has("chimera") and kinds.has("charybdis"), "Skylla, Cerberus, Cetus, Echidna, the Hydra, the Chimera and Charybdis")


## A creature that hunted you follows you out of its signal into the system,
## at your speed, attacking NPC ships in its path; killed there, its loot.
func test_monster_follows_you_out() -> void:
	var main: Node = await _game()
	var site: SignalSite = await _enter_kind(main, "monster")
	var m: Node2D = site._monster
	main.ship.hull = 99999.0
	main.ship.max_hull = 99999.0
	main.ship.global_position = m.global_position + Vector2(0, 700)
	for i in 30:
		await tree.process_frame
	check(m.hunting, "it hunts you once it sees you")
	check(is_equal_approx(m.max_speed, main.ship.max_speed), "at your ship's speed (%d / %d)" % [m.max_speed, main.ship.max_speed])
	main.ship.global_position = m.global_position + Vector2(0, 3000)
	m._retarget_cd = 0.0
	await tree.process_frame
	await tree.process_frame
	check(m._target == main.ship, "out of its aggro range it keeps after you")
	var hull: float = m.hull - 500.0
	m.hull = hull
	site.leave()
	await tree.process_frame
	var p := main.get_node_or_null("MonsterPursuit") as MonsterPursuit
	check(p != null and is_instance_valid(m) and not m.visible, "it follows you out (not yet in sight)")
	if p == null:
		return
	p._wait = 0.05
	for i in 10:
		await tree.process_frame
	check(m.visible and m.global_position.distance_to(main.ship.global_position) < MonsterPursuit.SURFACE + 400.0, "it comes out of the void beside you")
	check(is_equal_approx(m.hull, hull), "as hurt as you left it")
	check(m._target == main.ship, "hunting you")
	check(not main.get_save_data()["enemies"].any(func(d): return d.get("type") == m.type_id), "not saved")
	# An NPC ship in its path is attacked.
	var npc: Node2D = main.spawn_ship(m.global_position + Vector2(200, 0), EnemyTypes.neutral_ids()[0])
	m._retarget_cd = 0.0
	await tree.process_frame
	await tree.process_frame
	check(m._target == npc, "an NPC ship in its path is attacked")
	npc.queue_free()
	# Killed out here: loot, the signal done.
	var sg: Dictionary = p.sig
	m.take_damage(999999.0, m.global_position)
	var t0 := Time.get_ticks_msec()
	while is_instance_valid(m) and Time.get_ticks_msec() - t0 < 6000:
		await tree.process_frame
	check(not is_instance_valid(m) and sg["done"], "killed in the system: the signal is done")
	check(tree.get_nodes_in_group("pickups").any(func(q): return q.get("item_id") == "alien_alloy"), "and it drops the alloy")


## Running from a creature doesn't outrun its bullets: fired at you fleeing,
## they fly faster (SpaceMonster._orb).
func test_bullets_catch_you_fleeing() -> void:
	var main: Node = await _game()
	var e: Node2D = main.spawn_ship(main.ship.global_position + Vector2(0, -700), "skylla")
	for i in 3:
		await tree.process_frame
	var mon: SpaceMonster = e.body.get_node("Monster")
	e._target = main.ship
	main.ship.velocity = Vector2.ZERO
	var still: float = mon._orb(Vector2(150, 0), SpaceMonster.ORB_COLOR).velocity.length()
	main.ship.velocity = Vector2(0, main.ship.max_speed)   # (straight away from it)
	var fleeing: float = mon._orb(Vector2(150, 0), SpaceMonster.ORB_COLOR).velocity.length()
	check(is_equal_approx(still, 150.0), "holding still: its bullets at their own speed (%d)" % still)
	check(fleeing > main.ship.max_speed, "fleeing at full speed: faster than you (%d vs %d)" % [fleeing, main.ship.max_speed])
	e.queue_free()


## Every signal has a level (easy, moderate, hard, insane), shown, that
## multiplies its hostiles' hull, shields and damage - and its rewards.
func test_signal_levels() -> void:
	var seen := {}
	for e in 6:
		for sg in SignalSites.generate(Galaxy.HOME, e):
			check(SignalSites.LEVELS.has(sg.get("level", "")), "each signal has a level (%s)" % sg.get("level"))
			seen[sg["level"]] = true
	check(seen.size() >= 3, "levels vary (%s)" % str(seen.keys()))
	check(SignalSites.level({"seed": 7}) == SignalSites.level({"seed": 7}), "an old save's signal gets the same level every time")
	check(SignalSites.title({"kind": "monster", "level": "insane"}) == "Unknown bio-signature (Insane)", "its title shows it")
	var main: Node = await _game()
	var sg := _signal("monster")
	sg["level"] = "insane"
	var site: SignalSite = await _enter_kind(main, "monster")
	var m: Node2D = site._monster
	var base: Dictionary = EnemyTypes.get_type(m.type_id)
	check(is_equal_approx(m.max_hull, float(base["hull"]) * 2.25) and is_equal_approx(m.hull, m.max_hull), "insane: hull x2.25")
	check(is_equal_approx(m.max_shields, float(base["shields"]) * 2.25), "and shields x2.25")
	for attempt in 8:
		# (A hit may damage one of the ship's parts - Parts - and its stats are
		# applied again, the hull here with them: that hit doesn't count.)
		main.player_data.condition.clear()
		main.ship.max_hull = 1000.0
		main.ship.hull = 1000.0
		main.ship.shields = 0.0
		main.ship.take_damage(10.0, m.global_position, m)
		if is_equal_approx(main.ship.max_hull, 1000.0):
			break
	check(is_equal_approx(main.ship.hull, 1000.0 - 22.5), "and its damage x2.25 (%s)" % main.ship.hull)
	check(site._title != null and site._title.get_parent().get_children().any(func(c): return c is Label and c.text.begins_with("INSANE")), "the panel shows the level")
	var p := site._drop(main.ship.global_position, "credits", 100)
	check(p.amount == 225, "rewards x2.25 (%d)" % p.amount)
