class_name SignalSite
extends Node2D
## A signal source you've dropped into (SignalSites, from a SignalBeacon's
## ENTER): a pocket of empty space - no star, planets or stations, only the
## deep sky - where its encounter plays out. It lives far out in the space
## scene (ORIGIN), so ships, weapons, loot and the HUD all work as anywhere;
## main.site points at it while you're here. A panel at the top says what's
## going on (at the bottom, above the toolbar), with a Leave button (or fly out past BOUNDS); you come back out
## beside the beacon. Finishing it (done) marks the signal done - it won't
## be there next time. Saving here saves you at the beacon.
##
##   stranded     a ship out of fuel: fly up to it and transfer 5 fuel (or rig
##                its drive with 2 energy cells) - credits and its empire's
##                thanks; one time in three it was bait, and pirates jump you
##   under_attack a freighter (tougher than usual) fighting 3-4 pirates: kill
##                them while it lives for its reward
##   wreck        a wrecked hull, 10-14 pieces of loot drifting round it (kept,
##                not expiring); scavengers may turn up
##   monster      a creature - Skylla (SeaWitch), Cerberus (CerberusBeast), Cetus (CetusBeast)
##                Echidna (EchidnaBeast), the Hydra (HydraBeast), the Chimera
##                (ChimeraBeast) or Charybdis (CharybdisBeast),
##                by the signal: kill it for alien alloy, data cores, credits
##   anomaly      a swirling anomaly with four nodes round it: right-click each
##                (close up) to scan it - research data for all four; its core
##                burns
##   ring         not a signal: a ringed planet's ring (its beacon rides on the
##                ring - main.gd), a local space of its own: ice asteroids beyond
##                counting along a curving band, miners of the system's empire
##                (or independents) cutting them, pirate raids every minute or
##                so. Mine the ice, or defend the miners - each raider you
##                destroy while they work earns their empire's thanks
##                (RING_DEFEND_REP). It never finishes: leave when you like.
##   deathtrap    a 5,200-long field of unstable anomalies (draining shields,
##                then burning the hull) with one winding safe line through;
##                its exit holds the prize. Flying out of the field's sides
##                leaves the site with nothing.

const ORIGIN := Vector2(240000.0, 240000.0)
const BOUNDS := 7000.0              # this far from ORIGIN: you leave the site
const STRANDED_REACH := 420.0
const HAZARD_DRAIN := 45.0          # per second inside a hazard (shields, then hull)
const CORE_BURN := 30.0
const FIELD_LENGTH := 5200.0
const FIELD_HALF_WIDTH := 1800.0
## The ring: its band (an arc of a circle this big, centred below), its rocks
## and miners, how often raiders come, and what defending the miners earns.
const RING_RADIUS := 26000.0
const RING_WIDTH := 1800.0
const RING_ROCKS := 100
const RING_MINERS := 5
const RING_RAID_EVERY := [55.0, 85.0]
const RING_DEFEND_REP := 1.5
## Ships collide with the ring's ice: pushed out and bounced (RING_BOUNCE of
## the speed into the rock comes back); a hit faster than RING_SAFE_SPEED
## hurts - RING_IMPACT_DAMAGE per unit of speed over it (kinetic).
const RING_BOUNCE := 0.45
const RING_SAFE_SPEED := 90.0
const RING_IMPACT_DAMAGE := 0.12
const RING_CELL := 400.0
const PLAYER_RADIUS := 38.0

var main: Node
var sig: Dictionary = {}
var kind := ""
var return_point := Vector2.ZERO
var done := false
var status := ""
var in_hazard := false
var spawned: Array = []             # ships made here (freed on leaving)
var hazards: Array = []             # deathtrap: [{pos, r, ph}]
var path: PackedVector2Array        # deathtrap: the safe line through (entry -> exit)
var exit_point := Vector2.ZERO
var scan_points: Array = []         # anomaly: ScanNode
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _victim: Node2D                 # stranded / under_attack: the ship to help
var _pirates: Array = []
var _monster: Node2D
var _loot: Array = []
var _ambush := false
var _ambushed := false
var _leaving := false
var _rocks: Array = []              # ring: its asteroids (in main's asteroids, freed on leaving)
var _miners: Array = []
var _miner_empire := ""
var _raid_t := 0.0
var _thanked := {}                  # ring: raiders already counted (instance ids)
var _rock_grid := {}                # ring: Vector2i cell -> its rocks (they don't move)
var _bump_t := {}                   # ring: ship instance id -> time of its last hurting hit
var _layer: CanvasLayer
var _title: Label
var _status: Label
var _action: Button
var _warn: Label


func _ready() -> void:
	z_index = -1


## Builds the encounter and brings the ship in.
func start() -> void:
	kind = str(sig.get("kind", "wreck"))
	_rng.seed = int(sig.get("seed", 1))
	position = Vector2.ZERO
	_build_ui()
	var ship: Node2D = main.ship
	ship.stop()
	ship.set_attack_target(null)
	ship.velocity = Vector2.ZERO
	var entry := ORIGIN
	match kind:
		"stranded": _build_stranded()
		"under_attack": _build_under_attack()
		"wreck": _build_wreck()
		"monster": _build_monster()
		"anomaly": _build_anomaly()
		"deathtrap":
			_build_deathtrap()
			entry = path[0]
		"ring": _build_ring()
	ship.global_position = entry
	ship.rotation = (exit_point - entry).angle() + PI / 2.0 if kind == "deathtrap" else 0.0
	main.get_node("Ship/Camera2D").reset_smoothing()
	_fade_in()
	Sfx.play("space/jump")
	if kind == "ring":
		GameLog.post("Into the ring of %s (local space)." % str(sig.get("planet", "the planet")), "mission")
	else:
		GameLog.post("Dropped into the signal source: %s." % SignalSites.title(sig), "mission")


func title() -> String:
	if kind == "ring":
		return "The ring of %s" % str(sig.get("planet", "the planet"))
	return SignalSites.info(kind)["name"]


func _say(text: String) -> void:
	status = text
	if _status:
		_status.text = text


## Done: the signal won't be there again.
func complete(text: String) -> void:
	if done:
		return
	done = true
	sig["done"] = true
	_say(text + "  ·  Leave when you're ready.")
	GameLog.post("Signal source: " + text, "good")
	Sfx.play("space/scan_done")
	# A reward of gear (Gear: for the ship or your automaton) - better the
	# harder the signal; two from an insane one.
	var lvl: float = {"easy": 0.2, "moderate": 0.45, "hard": 0.7, "insane": 1.0}.get(SignalSites.level(sig), 0.45)
	if is_instance_valid(main) and is_instance_valid(main.ship):
		for k in (2 if lvl >= 1.0 else 1):
			_drop(main.ship.global_position + Vector2.from_angle(_rng.randf() * TAU) * 90.0, Gear.roll(_rng, "", lvl), 1)


# --- The encounters ---------------------------------------------------------------------

func _civilian_type() -> String:
	# (the system owner's own freighter design: it flies for them - _empire())
	var own := ShipDesigns.pick(_empire(), ["trader"])
	if own != "":
		return own
	var ids: Array = EnemyTypes.neutral_ids().filter(func(id): return EnemyTypes.get_type(id).get("role", "") == "trader")
	if ids.is_empty():
		ids = EnemyTypes.neutral_ids()
	return ids[_rng.randi() % ids.size()]


func _empire() -> String:
	var e: String = Galaxy.owner_of(Galaxy.current_system)
	return Galaxy.HOME_EMPIRE if e == "pirates" else e


func _spawn(at: Vector2, type_id := "", empire := "pirates") -> Node2D:
	var s: Node2D = main.spawn_ship(at, type_id, {}, empire)
	s.home = at
	if empire == "pirates":   # hostiles: the signal's level
		apply_level(s)
	spawned.append(s)
	return s


## A hostile here: hull, shields and damage x the signal's level.
func apply_level(s: Node2D) -> void:
	var m := SignalSites.mult(sig)
	s.max_hull *= m
	s.hull = s.max_hull
	s.max_shields *= m
	s.shields = s.max_shields
	s.damage_mult = m


func _pirate_wave(n: int, around: Vector2, dist: float) -> Array:
	var out := []
	for i in n:
		out.append(_spawn(around + Vector2.from_angle(_rng.randf() * TAU) * dist))
	return out


func _build_stranded() -> void:
	_victim = _spawn(ORIGIN + Vector2(0, -900), _civilian_type(), _empire())
	_victim.max_speed = 0.0
	_victim.velocity = Vector2.ZERO
	_victim.display_name = "Stranded " + _victim.display_name
	_ambush = _rng.randf() < 0.35
	_say("A %s is drifting without fuel. Fly up to it and transfer 5 fuel (or 2 energy cells)." % _victim.display_name)


func _build_under_attack() -> void:
	_victim = _spawn(ORIGIN + Vector2(0, -1100), _civilian_type(), _empire())
	_victim.max_hull *= 3.0
	_victim.hull = _victim.max_hull
	_victim.max_speed *= 0.4
	_victim.cargo = {"machinery": 12, "electronics": 8}
	_pirates = _pirate_wave(_rng.randi_range(3, 4), _victim.global_position, 380.0)
	_say("Pirates are attacking a %s. Destroy them before they destroy it." % _victim.display_name)


func _build_wreck() -> void:
	var at := ORIGIN + Vector2(0, -800)
	var w := WreckProp.new()
	w.position = at
	w.seed_ = int(sig.get("seed", 1))
	add_child(w)
	var table := [["scrap", 2, 4], ["scrap", 2, 4], ["energy_cell", 1, 3], ["alien_alloy", 1, 2], ["credits", 40, 140],
		["credits", 40, 140], ["repair_kit", 1, 1], ["missile", 2, 4], ["machinery", 2, 5], ["electronics", 2, 4]]
	for i in _rng.randi_range(10, 14):
		var e: Array = table[_rng.randi() % table.size()]
		_drop(at + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(120.0, 520.0), e[0], _rng.randi_range(e[1], e[2]))
	if _rng.randf() < 0.4:
		_drop(at + Vector2.from_angle(_rng.randf() * TAU) * 200.0, "data_core", 1)
	_ambush = _rng.randf() < 0.3
	_say("A wrecked ship, its cargo drifting round it. Collect the salvage (%d pieces)." % _loot.size())


## The creatures of the monster signals: [type, name, the warning, her / his / its].
const CREATURES := [
	["skylla", "Skylla", "Something vast stirs here: Skylla, the sea witch of the deep void. Kill her - her flesh is laced with alien alloy.", "her"],
	["cerberus", "Cerberus", "Three heads lift as one and howl: Cerberus, the hound at the gates of the dead. Kill it - its hide is laced with alien alloy.", "its"],
	["cetus", "Cetus", "The void heaves like a sea and something vast surfaces: Cetus, the monster Poseidon sent against Andromeda. Kill it - its hide is laced with alien alloy.", "its"],
	["echidna", "Echidna", "Coils of gold-banded scales unwind in the dark and a woman's face looks out of them: Echidna, the mother of monsters. Kill her - her scales are laced with alien alloy.", "her"],
	["hydra", "The Hydra", "Eight heads rise hissing from one knot of coils: the Hydra of Lerna. Cut off a head and it grows back - kill the whole beast; its hide is laced with alien alloy.", "its"],
	["chimera", "The Chimera", "A lion's roar, a goat's bleat and a serpent's hiss from one throat: the Chimera stalks out of the dark. Kill it - its hide is laced with alien alloy.", "its"],
	["charybdis", "Charybdis", "The void begins to turn, faster and faster, round a ring of teeth: Charybdis, the whirlpool that swallows the sea. Don't get drawn in - kill it; its hide is laced with alien alloy.", "its"],
]
var _creature: Array = CREATURES[0]
var _monster_at := ORIGIN


func _build_monster() -> void:
	_creature = CREATURES[absi(hash(str(sig.get("id", "")))) % CREATURES.size()]   # (the same signal: the same creature)
	var p := main.get_node_or_null("MonsterPursuit") as MonsterPursuit
	if p and p.sig.get("id") == sig.get("id"):   # (it followed you out: it's back, as hurt as it was)
		_monster = p.give_back()
		_monster.global_position = ORIGIN + Vector2(0, -1300)
		_monster.home = _monster.global_position
		_monster.velocity = Vector2.ZERO
		spawned.append(_monster)
	else:
		_monster = _spawn(ORIGIN + Vector2(0, -1300), _creature[0], "pirates")
	_monster.aggro_range = 950.0
	Sfx.play("space/monster_roar")
	_say(_creature[2])


func _build_anomaly() -> void:
	var core := Anomaly.new()
	core.position = ORIGIN + Vector2(0, -1200)
	add_child(core)
	for i in 4:
		var n := ScanNode.new()
		n.site = self
		n.position = core.position + Vector2.from_angle(i * TAU / 4.0 + _rng.randf_range(-0.3, 0.3)) * _rng.randf_range(650.0, 950.0)
		n.display_name = "Anomaly node %d" % (i + 1)
		add_child(n)
		scan_points.append(n)
	_say("A space anomaly. Fly close to each of its 4 nodes and right-click it to scan (0 / 4). Keep clear of the core.")


# --- The ring --------------------------------------------------------------------------------

## The band's centre: far below, so the ring curves gently across the pocket.
func _ring_centre() -> Vector2:
	return ORIGIN + Vector2(0, RING_RADIUS)


func _build_ring() -> void:
	var c := _ring_centre()
	for i in RING_ROCKS:
		var a := -PI / 2.0 + _rng.randf_range(-0.17, 0.17)
		var p := c + Vector2.from_angle(a) * (RING_RADIUS + _rng.randf_range(-RING_WIDTH, RING_WIDTH) * 0.5)
		if p.distance_to(ORIGIN) < 350.0:
			continue   # (not on top of you as you come in)
		var d := Asteroid.random_data(p)
		d["kind"] = "ice"
		d["radius"] = _rng.randf_range(34.0, 95.0)
		d["seed"] = _rng.randi()
		var rock: Node2D = main.spawn_asteroid(d)
		_rocks.append(rock)
		var cell := Vector2i(floori(p.x / RING_CELL), floori(p.y / RING_CELL))
		if not _rock_grid.has(cell):
			_rock_grid[cell] = []
		_rock_grid[cell].append(rock)
	var o := Galaxy.owner_of(Galaxy.current_system)
	_miner_empire = o if o in Galaxy.MAJOR and _rng.randf() < 0.7 else "independent"
	for i in RING_MINERS:
		_add_miner()
	_raid_t = _rng.randf_range(15.0, 30.0)
	_say_ring()


func _add_miner() -> void:
	var id := ShipDesigns.pick(_miner_empire, ["miner"])
	if id == "":
		id = ShipDesigns.pick("independent", ["miner"])
	if id == "":
		return
	var c := _ring_centre()
	var at := c + Vector2.from_angle(-PI / 2.0 + _rng.randf_range(-0.2, 0.2)) * RING_RADIUS
	var m := _spawn(at, id, _miner_empire if ShipDesigns.owner_of(id) == _miner_empire else "independent")
	_miners.append(m)


func _say_ring() -> void:
	var alive := _miners.filter(func(m): return is_instance_valid(m) and m.is_alive()).size()
	var raiders := _pirates.filter(func(p): return is_instance_valid(p) and p.is_alive()).size()
	var who := Galaxy.empire_name(_miner_empire) if _miner_empire != "independent" else "independent"
	_say("The ring of %s  ·  %d %s miners cutting ice%s  ·  mine the ice, or defend the miners - their empire will thank you" % [
		str(sig.get("planet", "the planet")), alive, who if _miner_empire == "independent" else Galaxy.EMPIRES[_miner_empire]["short"],
		("  ·  %d RAIDERS!" % raiders) if raiders > 0 else ""])


## Ships against the ice: every ship here (you, the miners, the raiders) is
## checked against the rocks in its cell and the next ones (a grid built once:
## rocks don't move) - overlapping, it's pushed out and bounced; a hard hit
## hurts (at most every half second).
func _ring_collisions() -> void:
	var ships: Array = [main.ship] + spawned.filter(func(x): return is_instance_valid(x) and x.is_alive())
	for sh in ships:
		if not is_instance_valid(sh) or not sh.is_alive():
			continue
		var r: float = PLAYER_RADIUS if sh == main.ship else float(sh.get("hit_radius"))
		var c := Vector2i(floori(sh.global_position.x / RING_CELL), floori(sh.global_position.y / RING_CELL))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for rock in _rock_grid.get(c + Vector2i(dx, dy), []):
					if is_instance_valid(rock) and rock.is_alive():
						_bump(sh, r, rock)


func _bump(sh: Node2D, r: float, rock: Node2D) -> void:
	var off: Vector2 = sh.global_position - rock.global_position
	var reach: float = r + rock.hit_radius
	var dist := off.length()
	if dist >= reach or dist < 0.001:
		return
	var n := off / dist
	sh.global_position = rock.global_position + n * reach   # (out of the rock)
	var v: Vector2 = sh.velocity
	var into := v.dot(n)   # (negative: moving into it)
	if into >= 0.0:
		return
	sh.velocity = v - (1.0 + RING_BOUNCE) * into * n
	var speed := -into
	if speed <= RING_SAFE_SPEED:
		return
	var id := sh.get_instance_id()
	if _t - float(_bump_t.get(id, -10.0)) < 0.5:
		return
	_bump_t[id] = _t
	var hit_at: Vector2 = rock.global_position + n * rock.hit_radius
	sh.take_damage((speed - RING_SAFE_SPEED) * RING_IMPACT_DAMAGE, hit_at, null, "kinetic")
	Effects.debris(hit_at, Color(0.85, 0.93, 1.0), 0.5)
	if sh == main.ship:
		Sfx.play_world("space/rock_break", hit_at, -4.0)
		main.hud.flash_message("Hit the ice!")


func _run_ring(ship: Node2D, delta: float) -> void:
	_ring_collisions()
	# Raiders come for the miners now and then.
	_raid_t -= delta
	if _raid_t <= 0.0:
		_raid_t = _rng.randf_range(RING_RAID_EVERY[0], RING_RAID_EVERY[1])
		var c := _ring_centre()
		var at := c + Vector2.from_angle(-PI / 2.0 + (0.26 if _rng.randf() < 0.5 else -0.26)) * RING_RADIUS
		_pirates += _pirate_wave(_rng.randi_range(2, 4), at, 300.0)
		main.hud.flash_message("Raiders in the ring - they're after the miners!")
		GameLog.post("Raiders have come into the ring for its miners.", "danger")
	# Each raider you destroy while miners are at work: their empire's thanks.
	var working := _miners.any(func(m): return is_instance_valid(m) and m.is_alive())
	for p in _pirates:
		if not is_instance_valid(p) or p.is_alive() or _thanked.has(p.get_instance_id()):
			continue
		_thanked[p.get_instance_id()] = true
		if working and p.last_attacker == ship:
			Galaxy.change_reputation(_miner_empire, RING_DEFEND_REP, "you defended the ring's miners")
	_pirates = _pirates.filter(func(p): return is_instance_valid(p) and p.is_alive())
	# Miners off to sell their ice (or lost) - others come out in time.
	for m in _miners.duplicate():
		if not is_instance_valid(m) or not m.is_alive() or m.global_position.distance_to(ORIGIN) > BOUNDS * 0.9:
			_miners.erase(m)
			if is_instance_valid(m) and m.is_alive():
				spawned.erase(m)
				m.queue_free()
	if _miners.size() < RING_MINERS and _rng.randf() < delta / 20.0:
		_add_miner()
	if int(_t * 2.0) % 2 == 0:
		_say_ring()


func _build_deathtrap() -> void:
	var dir := Vector2.from_angle(_rng.randf() * TAU)
	var side := dir.orthogonal()
	var start := ORIGIN - dir * FIELD_LENGTH * 0.5
	# The safe line: a winding path from the entry to the exit.
	path = PackedVector2Array()
	var n := 7
	for i in n + 1:
		var lat := 0.0 if i == 0 or i == n else _rng.randf_range(-900.0, 900.0)
		path.append(start + dir * (FIELD_LENGTH * i / n) + side * lat)
	exit_point = path[path.size() - 1]
	# Hazards everywhere else in the field, clear of the line.
	var step := 300.0
	var x := 250.0
	while x < FIELD_LENGTH - 250.0:
		var y := -FIELD_HALF_WIDTH + 150.0
		while y < FIELD_HALF_WIDTH - 150.0:
			var p := start + dir * (x + _rng.randf_range(-80, 80)) + side * (y + _rng.randf_range(-80, 80))
			var r := _rng.randf_range(140.0, 230.0)
			if _dist_to_path(p) > r + 210.0:
				hazards.append({"pos": p, "r": r, "ph": _rng.randf() * TAU})
			y += step
		x += step
	_say("An unstable anomaly field. Its storms drain shields and burn hulls - follow the gaps to the exit beacon. Fly out of the sides and you lose the prize.")


func _dist_to_path(p: Vector2) -> float:
	var best := INF
	for i in path.size() - 1:
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, path[i], path[i + 1])))
	return best


## Loot that stays (doesn't expire) until you take it.
func _drop(at: Vector2, id: String, n: int) -> Pickup:
	n = maxi(1, roundi(n * SignalSites.mult(sig)))   # (rewards x the signal's level)
	var p := Pickup.spawn(get_tree(), at, id, n)
	p.permanent = true
	p.velocity *= 0.15
	_loot.append(p)
	return p


# --- Running ------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _leaving or main == null:
		return
	var ship: Node2D = main.ship
	if not ship.is_alive():
		return
	in_hazard = false
	match kind:
		"stranded": _run_stranded(ship)
		"under_attack": _run_under_attack()
		"wreck": _run_wreck(ship)
		"monster": _run_monster()
		"anomaly": _run_anomaly(ship, delta)
		"deathtrap": _run_deathtrap(ship, delta)
		"ring": _run_ring(ship, delta)
	if _warn:
		_warn.visible = in_hazard
	if ship.global_position.distance_to(ORIGIN) > BOUNDS or (kind == "deathtrap" and not done and _outside_field(ship.global_position)):
		leave()
	if kind != "ring":   # (the ring's band is still: drawn once)
		queue_redraw()


func _run_stranded(ship: Node2D) -> void:
	if done or not is_instance_valid(_victim) or not _victim.is_alive():
		_action.visible = false
		if not done and not is_instance_valid(_victim):
			done = true
			sig["done"] = true
			_say("The stranded ship is lost.  ·  Leave when you're ready.")
		return
	_victim.velocity = Vector2.ZERO
	var d := ship.global_position.distance_to(_victim.global_position)
	if _ambush and not _ambushed and d < 900.0:
		_ambushed = true
		_pirates = _pirate_wave(2, ship.global_position, 1300.0)
		main.hud.flash_message("It was bait - pirates are jumping you!")
		GameLog.post("The distress call was a trap: pirates incoming.", "danger")
	_action.visible = d < STRANDED_REACH
	var data: Node = main.player_data
	if data.count("fuel") >= 5:
		_action.text = "Transfer 5 fuel"
		_action.disabled = false
	elif data.count("energy_cell") >= 2:
		_action.text = "Rig their drive (2 energy cells)"
		_action.disabled = false
	else:
		_action.text = "No fuel aboard - buy 5 at a market"
		_action.disabled = true


func _help_stranded() -> void:
	var data: Node = main.player_data
	if not data.remove_item("fuel", 5) and not data.remove_item("energy_cell", 2):
		return
	var pay := roundi(_rng.randi_range(250, 550) * SignalSites.mult(sig))
	data.add_credits(pay)
	if _victim.empire != "" and _victim.empire != "pirates":
		Galaxy.change_reputation(_victim.empire, 3.0)
	_victim.max_speed = EnemyTypes.get_type(_victim.type_id)["speed"]
	_victim.leg_target = _victim.global_position + Vector2.from_angle(_rng.randf() * TAU) * 9000.0
	_victim.has_leg = true
	_action.visible = false
	complete("You refuelled the %s. They paid %d drachmas and their empire won't forget it." % [_victim.display_name, pay])


func _run_under_attack() -> void:
	if done:
		return
	_pirates = _pirates.filter(func(p): return is_instance_valid(p) and p.is_alive())
	var alive: bool = is_instance_valid(_victim) and _victim.is_alive()
	if _pirates.is_empty():
		if alive:
			var pay := roundi(_rng.randi_range(450, 850) * SignalSites.mult(sig))
			main.player_data.add_credits(pay)
			if _victim.empire != "" and _victim.empire != "pirates":
				Galaxy.change_reputation(_victim.empire, 4.0)
			_victim.max_speed = EnemyTypes.get_type(_victim.type_id)["speed"]
			_victim.leg_target = _victim.global_position + Vector2.from_angle(_rng.randf() * TAU) * 9000.0
			_victim.has_leg = true
			complete("You saved the %s - it sent %d drachmas as thanks." % [_victim.display_name, pay])
		else:
			complete("The pirates are dead, but the freighter was lost. Its cargo is drifting where it died.")
	elif not alive:
		_say("The freighter is lost. %d pirates remain." % _pirates.size())
	else:
		_say("Pirates attacking the %s: %d left. Its hull: %d %%." % [_victim.display_name, _pirates.size(), int(_victim.hull / _victim.max_hull * 100.0)])


func _run_wreck(ship: Node2D) -> void:
	_loot = _loot.filter(func(p): return is_instance_valid(p))
	if _ambush and not _ambushed and _t > 12.0:
		_ambushed = true
		_pirate_wave(_rng.randi_range(2, 3), ship.global_position, 1400.0)
		main.hud.flash_message("Scavengers - pirates want the salvage too!")
		GameLog.post("Pirate scavengers arrive at the wreck.", "danger")
	if done:
		return
	if _loot.is_empty():
		complete("You stripped the wreck of everything worth taking.")
	else:
		_say("A wrecked ship, its cargo drifting round it: %d pieces of salvage left." % _loot.size())


func _run_monster() -> void:
	if done:
		return
	if is_instance_valid(_monster):
		_monster_at = _monster.global_position
		if _monster.is_alive():
			_say("%s: %d %% left." % [_creature[1], int(_monster.hull / _monster.max_hull * 100.0)])
		return   # (alive, or dying: the loot comes after the explosion)
	var at := _monster_at
	_drop(at, "alien_alloy", _rng.randi_range(3, 5))
	_drop(at + Vector2(40, 0), "data_core", _rng.randi_range(1, 2))
	_drop(at + Vector2(-40, 20), "credits", _rng.randi_range(500, 900))
	complete("%s is dead. The body is breaking up - collect what %s leaves." % [_creature[1], "she" if _creature[3] == "her" else "it"])


func _run_anomaly(ship: Node2D, delta: float) -> void:
	var core: Node2D = null
	for c in get_children():
		if c is Anomaly:
			core = c
	if core and ship.global_position.distance_to(core.global_position) < core.RADIUS:
		in_hazard = true
		ship.hazard_damage(CORE_BURN * SignalSites.mult(sig) * delta, core.global_position)
	if done:
		return
	var n := scan_points.filter(func(s): return s.scanned).size()
	if n >= scan_points.size():
		_drop(ship.global_position + Vector2(60, 0), "research_data", 2)
		_drop(ship.global_position + Vector2(-60, 0), "credits", 150)
		complete("All four nodes scanned: 2 Anomaly Research Data (research stations pay well).")
	else:
		_say("A space anomaly: %d / %d nodes scanned. Fly close to a node and right-click it. Keep clear of the core." % [n, scan_points.size()])


## The node under `world` a right-click scans (anomaly sites), or null.
func scan_point_at(world: Vector2) -> Node2D:
	for s in scan_points:
		if not s.scanned and s.global_position.distance_to(world) < s.hit_radius * 1.6:
			return s
	return null


func _run_deathtrap(ship: Node2D, delta: float) -> void:
	var p: Vector2 = ship.global_position
	for h in hazards:
		if p.distance_to(h["pos"]) < _hazard_r(h) + 20.0:
			in_hazard = true
			ship.hazard_damage(HAZARD_DRAIN * SignalSites.mult(sig) * delta, h["pos"])
			break
	if not done and p.distance_to(exit_point) < 220.0:
		_drop(exit_point + Vector2(80, 0), "alien_alloy", _rng.randi_range(2, 3))
		_drop(exit_point + Vector2(-80, 0), "data_core", 1)
		_drop(exit_point + Vector2(0, 80), "credits", _rng.randi_range(400, 700))
		complete("You crossed the anomaly field. Its heart held a cache of exotic salvage.")


func _hazard_r(h: Dictionary) -> float:
	return float(h["r"]) * (1.0 + 0.08 * sin(_t * 1.7 + float(h["ph"])))


func _outside_field(p: Vector2) -> bool:
	var a := path[0]
	var dir := (exit_point - a).normalized()
	var along := (p - a).dot(dir)
	var lat := absf((p - a).dot(dir.orthogonal()))
	return lat > FIELD_HALF_WIDTH + 150.0 or along < -500.0 or along > FIELD_LENGTH + 500.0


## Back out beside the beacon; everything made here goes.
func leave() -> void:
	if _leaving:
		return
	_leaving = true
	# A creature still hunting you follows you out (MonsterPursuit).
	if kind == "monster" and not done and is_instance_valid(_monster) and _monster.is_alive() and _monster.hunting \
			and main.get_node_or_null("MonsterPursuit") == null:
		spawned.erase(_monster)
		MonsterPursuit.start(main, _monster, sig, _creature)
	for s in spawned:
		if is_instance_valid(s):
			s.queue_free()
	for p in _loot:
		if is_instance_valid(p):
			p.queue_free()
	for r in _rocks:
		if is_instance_valid(r):
			r.queue_free()
	for p in get_tree().get_nodes_in_group("pickups"):
		if p.global_position.distance_to(ORIGIN) < BOUNDS * 1.5:
			p.queue_free()
	for o in get_tree().get_nodes_in_group("monster_orbs"):
		o.queue_free()
	var ship: Node2D = main.ship
	ship.stop()
	ship.set_attack_target(null)
	ship.velocity = Vector2.ZERO
	ship.global_position = return_point
	main.get_node("Ship/Camera2D").reset_smoothing()
	main.site = null
	Sfx.play("space/jump")
	if kind == "ring":
		GameLog.post("Left the ring of %s." % str(sig.get("planet", "the planet")), "mission")
	else:
		GameLog.post("Left the signal source%s." % ("" if done else " (unfinished - its beacon is still there)"), "mission")
	_fade_in()
	_layer.queue_free()
	queue_free()


func _fade_in() -> void:
	var l := CanvasLayer.new()
	l.layer = 60
	var r := ColorRect.new()
	r.color = Color(0.85, 0.9, 1.0, 1.0)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_child(r)
	main.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(r, "color", Color(0.02, 0.03, 0.08, 0.0), 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_callback(l.queue_free)


# --- The panel ----------------------------------------------------------------------------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 4
	main.add_child(_layer)
	var box := PanelContainer.new()
	var st := UI.panel_style(SignalSites.info(kind)["color"])
	st.bg_color = Color(0.04, 0.06, 0.12, 0.88)
	st.content_margin_left = 16
	st.content_margin_right = 16
	st.content_margin_top = 8
	st.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", st)
	box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)   # (above the toolbar: the top has the system's name and boss bars)
	box.position = Vector2(-330, -215)
	box.custom_minimum_size = Vector2(660, 0)
	box.mouse_filter = Control.MOUSE_FILTER_PASS
	_layer.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	box.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var head: String = ("LOCAL SPACE  ·  " + title().to_upper()) if kind == "ring" else "SIGNAL SOURCE  ·  " + str(SignalSites.info(kind)["name"]).to_upper()
	_title = UI.label(head, 17, SignalSites.info(kind)["color"])
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var level := SignalSites.level_info(sig)
	var lvl := UI.label(str(level["name"]).to_upper() + "  x%s" % str(level["mult"]), 16, level["color"])
	lvl.tooltip_text = "This signal's level: its enemies' hull, shields and damage - and its rewards - x%s" % str(level["mult"])
	lvl.mouse_filter = Control.MOUSE_FILTER_STOP
	lvl.visible = kind != "ring"   # (a ring is no signal: no level)
	top.add_child(lvl)
	_action = UI.button("", func(): _help_stranded(), 14)
	_action.visible = false
	top.add_child(_action)
	var lv := UI.button("Leave", leave, 14)
	lv.tooltip_text = "Back to solar space, beside the beacon. (Flying far out of this local space does the same.)"
	top.add_child(lv)
	_status = UI.label(status, 14, Color(0.9, 0.93, 1.0))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(620, 0)
	v.add_child(_status)
	_warn = UI.label("WARNING: inside an anomaly - shields draining, hull burning", 15, Color(1.0, 0.4, 0.35))
	_warn.visible = false
	v.add_child(_warn)


# --- Drawing (the deathtrap field) ---------------------------------------------------------

func _draw() -> void:
	if kind == "ring":
		# The band: faint dust along the arc, brighter at its heart.
		var c := _ring_centre()
		draw_arc(c, RING_RADIUS, -PI / 2.0 - 0.3, -PI / 2.0 + 0.3, 96, Color(0.7, 0.8, 0.9, 0.06), RING_WIDTH * 1.5)
		draw_arc(c, RING_RADIUS, -PI / 2.0 - 0.3, -PI / 2.0 + 0.3, 96, Color(0.8, 0.9, 1.0, 0.07), RING_WIDTH * 0.7)
		draw_arc(c, RING_RADIUS - RING_WIDTH * 0.2, -PI / 2.0 - 0.3, -PI / 2.0 + 0.3, 96, Color(0.85, 0.92, 1.0, 0.06), 90.0)
		return
	if kind != "deathtrap":
		return
	# Only the hazards on screen (a field has hundreds), their discs from the
	# baked one (batched; big draw_circles cost the field 4 ms a frame).
	var view := (get_canvas_transform().affine_inverse() * get_viewport_rect())
	var disc := ExhaustTrail.disc()
	for h in hazards:
		var c: Vector2 = h["pos"]
		var r := _hazard_r(h)
		if not view.grow(r * 1.25).has_point(c):
			continue
		var ph: float = h["ph"]
		for d in [[1.25, Color(0.6, 0.15, 0.7, 0.07)], [1.0, Color(0.55, 0.12, 0.6, 0.18)], [0.55, Color(0.95, 0.35, 0.9, 0.16)]]:
			var rr: float = r * d[0]
			draw_texture_rect(disc, Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, d[1])
		draw_arc(c, r, _t * 0.6 + ph, _t * 0.6 + ph + PI * 1.3, 24, Color(1.0, 0.5, 1.0, 0.5), 2.0, true)
		# Crackling arcs inside.
		if fmod(_t * 3.0 + ph, 1.0) < 0.35:
			var a := Vector2.from_angle(ph + floorf(_t * 3.0)) * r * 0.8
			var pts := PackedVector2Array([c, c + a * 0.35 + a.orthogonal() * 0.15, c + a * 0.65 - a.orthogonal() * 0.12, c + a])
			draw_polyline(pts, Color(1.0, 0.85, 1.0, 0.8), 2.0, true)
	# The field's edge (lines along its sides) and the exit beacon.
	var a := path[0]
	var dir := (exit_point - a).normalized()
	var side := dir.orthogonal() * FIELD_HALF_WIDTH
	for sgn in [-1.0, 1.0]:
		var p0: Vector2 = a + side * sgn
		var p1: Vector2 = exit_point + side * sgn
		var n := int(p0.distance_to(p1) / 80.0)
		for i in range(0, n, 2):
			draw_line(p0.lerp(p1, float(i) / n), p0.lerp(p1, float(i + 1) / n), Color(0.9, 0.4, 1.0, 0.35), 3.0)
	var pulse := 0.5 + 0.5 * sin(_t * 3.0)
	draw_circle(exit_point, 220.0, Color(0.4, 1.0, 0.7, 0.06 + 0.05 * pulse))
	draw_arc(exit_point, 160.0 + 20.0 * pulse, 0, TAU, 48, Color(0.4, 1.0, 0.7, 0.8), 3.0, true)
	var font := ThemeDB.fallback_font
	draw_string(font, exit_point + Vector2(-150, -200), "EXIT" if not done else "CLEARED", HORIZONTAL_ALIGNMENT_CENTER, 300, 22, Color(0.5, 1.0, 0.75))


# --- Pieces --------------------------------------------------------------------------------

## A wrecked ship: a hull broken in two, sparking, with plates drifting round.
class WreckProp extends Node2D:
	var seed_ := 1
	var _t := 0.0
	var _plates: Array = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_
		rotation = rng.randf() * TAU
		for i in 9:
			_plates.append([Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(140, 330), rng.randf_range(8, 22), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)])

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var hull := Color(0.33, 0.36, 0.42)
		var dark := Color(0.16, 0.17, 0.2)
		# The fore half and the aft half, drifting apart, jagged where they broke.
		var fore := PackedVector2Array([Vector2(-34, -40), Vector2(0, -150), Vector2(34, -40), Vector2(22, -22), Vector2(8, -34), Vector2(-6, -18), Vector2(-20, -30)])
		var aft := PackedVector2Array([Vector2(-48, 10), Vector2(-22, -4), Vector2(-8, 8), Vector2(10, -6), Vector2(30, 6), Vector2(48, 10), Vector2(56, 120), Vector2(-56, 120)])
		draw_set_transform(Vector2(0, -18), 0.12, Vector2.ONE)
		draw_colored_polygon(fore, hull)
		draw_polyline(fore + PackedVector2Array([fore[0]]), dark, 2.0, true)
		draw_set_transform(Vector2(6, 22), -0.08, Vector2.ONE)
		draw_colored_polygon(aft, hull.darkened(0.15))
		draw_polyline(aft + PackedVector2Array([aft[0]]), dark, 2.0, true)
		for k in 3:
			draw_rect(Rect2(Vector2(-40 + k * 30, 60), Vector2(18, 40)), Color(0.08, 0.08, 0.1))   # dead engines
		draw_set_transform(Vector2.ZERO)
		# Sparks along the break.
		for k in 4:
			if fmod(_t * 2.3 + k * 0.37, 1.0) < 0.25:
				var p := Vector2(-30 + k * 20, -10 + 6 * sin(k * 2.0))
				draw_circle(p, 3.0, Color(1.0, 0.85, 0.4))
				draw_circle(p, 7.0, Color(1.0, 0.6, 0.2, 0.25))
		# Hull plates drifting round it.
		for pl in _plates:
			var c: Vector2 = pl[0]
			var s: float = pl[1]
			var a: float = pl[2] + _t * float(pl[3])
			var q := PackedVector2Array([c + Vector2(-s, -s * 0.5).rotated(a), c + Vector2(s, -s * 0.7).rotated(a), c + Vector2(s * 0.8, s * 0.6).rotated(a), c + Vector2(-s * 0.7, s * 0.5).rotated(a)])
			draw_colored_polygon(q, hull.darkened(0.25))


## The anomaly's core: a swirl of light; flying into it burns.
class Anomaly extends Node2D:
	const RADIUS := 320.0
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		for k in 6:
			var r := RADIUS * (1.0 - k * 0.14)
			var col := Color.from_hsv(fmod(0.55 + k * 0.07 + _t * 0.03, 1.0), 0.6, 1.0, 0.1 + k * 0.03)
			draw_circle(Vector2.ZERO, r, col)
		for k in 5:
			var a := _t * (0.8 + k * 0.25) + k * 1.3
			draw_arc(Vector2.ZERO, RADIUS * (0.35 + k * 0.13), a, a + PI * 0.9, 32, Color(0.7, 0.9, 1.0, 0.55), 3.0, true)
		draw_circle(Vector2.ZERO, 26.0 + 6.0 * sin(_t * 4.0), Color(1, 1, 1, 0.9))


## One of the anomaly's nodes: right-click it close up to scan it (the
## ShipScanner's scan, within scan_range).
class ScanNode extends Node2D:
	var site: Node
	var display_name := "Anomaly node"
	var hit_radius := 46.0
	var scan_range := 520.0
	var scanned := false
	var _t := 0.0

	func on_scanned() -> void:
		scanned = true
		GameLog.post("%s scanned." % display_name, "info")

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Color(0.5, 1.0, 0.7) if scanned else Color(0.55, 0.8, 1.0)
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		draw_circle(Vector2.ZERO, hit_radius * (1.4 + 0.2 * pulse), Color(c, 0.1))
		for k in 3:
			var a := _t * (1.0 + k * 0.4) + k * 2.1
			draw_arc(Vector2.ZERO, hit_radius * (0.5 + k * 0.25), a, a + PI, 16, Color(c, 0.8), 2.5, true)
		draw_circle(Vector2.ZERO, 8.0, c)
		var font := ThemeDB.fallback_font
		var label := ("SCANNED" if scanned else "RIGHT-CLICK TO SCAN (close up)")
		draw_string_outline(font, Vector2(-160, hit_radius + 28), label, HORIZONTAL_ALIGNMENT_CENTER, 320, 14, 4, Color(0, 0, 0, 0.8))
		draw_string(font, Vector2(-160, hit_radius + 28), label, HORIZONTAL_ALIGNMENT_CENTER, 320, 14, c)
