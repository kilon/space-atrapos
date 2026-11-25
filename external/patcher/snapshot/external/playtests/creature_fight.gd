extends SceneTree
## Playtest: a monster signal fought to the kill with the starting ship.
##   godot --path . -s external/playtests/creature_fight.gd -- <skylla|cerberus|cetus|echidna|hydra|chimera|charybdis> [out_dir]
var main
var t0 := 0
var out := "/tmp"
func secs() -> float: return (Time.get_ticks_msec() - t0) / 1000.0
func log_(s: String) -> void: print("[%6.1f] %s" % [secs(), s])
func shot(n: String) -> void: root.get_viewport().get_texture().get_image().save_png(out + "/fight_%s.png" % n)
func _init():
	var args := OS.get_cmdline_user_args()
	var want: String = args[0] if args.size() > 0 else "skylla"
	if args.size() > 1: out = args[1]
	await process_frame
	var art = root.get_node("ProcArt")
	while not art.ready_done: await process_frame
	var G = root.get_node("Galaxy")
	G.new_game(false)
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in 90: await process_frame
	main.hud.hint.visible = false
	var SS = load("res://scripts/signal_site.gd")
	var sg: Dictionary = G.signals_in()[0].duplicate()
	var n := 0
	while true:
		sg["id"] = "play:%d" % n
		if SS.CREATURES[absi(hash(sg["id"])) % SS.CREATURES.size()][0] == want: break
		n += 1
	sg["kind"] = "monster"; sg["located"] = true
	G.signals_in().append(sg)
	main.refresh_beacons()
	var b = main._beacons[sg["id"]]
	main.ship.global_position = b.global_position
	main.enter_site(b)
	for i in 30: await process_frame
	var site = main.site
	var boss = site._monster
	var mon = boss.body.get_node("Monster")
	var ship = main.ship
	t0 = Time.get_ticks_msec()
	log_("%s: hull %d shields %d | you: hull %d shields %d, %s" % [boss.display_name, boss.hull, boss.shields, ship.hull, ship.shields, ship.weapon_id])
	ship.set_attack_target(boss, true)
	var prev_hp: float = ship.hull + ship.shields
	var dmg := 0.0
	var deaths := 0
	var shots := {}
	var last_rep := 0.0
	var dying_t := 0.0
	var strafe := 1.0
	var strafe_t := 0.0
	var last_sp := ""
	var sp_hp := 0.0
	var last_pat := ""
	while is_instance_valid(boss) and secs() < 600.0:
		await process_frame
		if not is_instance_valid(mon): break
		if not boss.is_alive() and not mon.dying: break
		var sp: String = mon.get("special") if mon.get("special") != null else ""
		if sp != last_sp:
			if sp != "": log_("SPECIAL: %s" % sp); sp_hp = ship.hull + ship.shields
			else: log_("  %s over - you lost %d" % [last_sp, int(sp_hp - ship.hull - ship.shields)])
			last_sp = sp
		if sp != "" and mon._sp > 1.0 and not shots.has(sp): shots[sp] = true; shot(sp)
		if sp != "" and mon._sp > 3.4 and not shots.has(sp + "_late"): shots[sp + "_late"] = true; shot(sp + "_late")
		if mon.pattern != last_pat:
			if mon.pattern != "": log_("attack: %s" % mon.pattern)
			last_pat = mon.pattern
		if mon.pattern != "" and mon._pt > 0.9 and not shots.has(mon.pattern): shots[mon.pattern] = true; shot(mon.pattern)
		if boss.is_alive() and sp == "whirlpool":   # fly straight out of the pull
			ship.move_to(boss.global_position + (ship.global_position - boss.global_position).normalized() * 1600.0)
		elif boss.is_alive() and sp in ["breath", "ram"] and mon.get_script().resource_path.ends_with("chimera_beast.gd"):   # out of the cone / the charge: sideways
			ship.move_to(ship.global_position + Vector2.from_angle(mon._aim).orthogonal() * mon._side * 500.0)
		elif boss.is_alive() and sp == "dive":   # dodge the breach: out of the ring once it shows
			if mon._sp > mon.SINK + mon.SUBMERGED:
				var out_dir: Vector2 = (ship.global_position - mon._to)
				if out_dir.length() < 40.0: out_dir = Vector2.from_angle(ship.rotation - PI / 2.0)
				ship.move_to(mon._to + out_dir.normalized() * 600.0)
		elif boss.is_alive() and sp != "":   # dodge: move across his aim
			var across: Vector2 = Vector2.from_angle(float(mon.get("_aim")) if mon.get("_aim") != null else 0.0).orthogonal()
			ship.move_to(ship.global_position + across * 500.0)
		elif boss.is_alive():
			strafe_t -= 1.0 / 60.0
			if mon.pattern != "" and mon._pt >= 0.0:
				if strafe_t <= 0.0:
					strafe = -strafe if randf() < 0.3 else strafe
					strafe_t = 1.5
				var away: Vector2 = (ship.global_position - boss.global_position)
				var want_p := away.normalized() * clampf(away.length(), 500.0, 750.0)
				ship.move_to(boss.global_position + want_p.rotated(0.5 * strafe))
			elif ship.get("attack_target") != boss or not ship.chasing:
				ship.set_attack_target(boss, true)
		var hp: float = ship.hull + ship.shields
		if hp < prev_hp and sp != "": log_("   hit %d during %s at %.2f s, %d from the breach point" % [prev_hp - hp, sp, mon._sp, ship.global_position.distance_to(mon.get("_to") if mon.get("_to") != null else boss.global_position)])
		if hp < prev_hp: dmg += prev_hp - hp
		prev_hp = hp
		if not ship.is_alive():
			deaths += 1
			log_("YOU DIED (%s at %d / %d)" % [boss.display_name, boss.hull, boss.max_hull])
			ship.set("_alive", true); ship.visible = true
			ship.hull = ship.max_hull; ship.shields = ship.max_shields
			prev_hp = ship.hull + ship.shields
			main.hud.game_over.hide()
			ship.set_attack_target(boss, true)
		if secs() - last_rep > 15.0:
			last_rep = secs()
			log_("status: %s %d/%d (+%d shields) | you hull %d shields %d | damage taken %d" % [boss.display_name, boss.hull, boss.max_hull, boss.shields, ship.hull, ship.shields, dmg])
			log_("   dist %d  boss target %s  ship target %s  boss state %s  ship order %s" % [ship.global_position.distance_to(boss.global_position), boss.get("_target"), ship.get("attack_target"), boss.get("state"), ship.get("_order")])
		if mon.dying and dying_t == 0.0:
			dying_t = secs(); log_("dying - death throes")
		if mon.dying and not shots.has("throes") and secs() - dying_t > 1.2: shots["throes"] = true; shot("throes")
	log_("FIGHT OVER: killed=%s  %.0f s  deaths %d  damage taken %d" % [not is_instance_valid(boss), secs(), deaths, dmg])
	var w := Time.get_ticks_msec()
	while is_instance_valid(site) and not site.done and Time.get_ticks_msec() - w < 3000: await process_frame
	log_("site done=%s" % (site.done if is_instance_valid(site) else "(left)"))
	quit()
