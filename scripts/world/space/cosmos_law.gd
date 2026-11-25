class_name CosmosLaw
extends Node
## The stations' law and their guns, and war at them (the 3D game's).
##
## Crime: firing on a trader or a patrol where a station sees it (within
## NOTICE) - a fine, taken from your credits (what you can't pay a debt: no
## pad till it's paid). Destroying one of them, or firing on a station, is
## murder: the system's stations open fire on you (their turrets - CosmosStation.
## turrets - heavy bolts, GUN_DAMAGE: they will destroy you), its patrols hunt
## you, for WANTED_TIME or till your ship is lost. Stations of an empire that
## holds you hostile shoot at you too.
## War: an empire's invasion fleet besieging your system (Fleets.besiegers) is
## there in ships - invaders circling the station they besiege, firing on it
## (Galaxy.damage_station: it burns below Galaxy.DAMAGED - explosions on it); its
## turrets fire back. Each one destroyed counts for your defence missions
## (Missions.on_enemy_killed) and against its fleet (Fleets.ship_lost). A
## station in trouble hails you as you come near (Cosmos.hail_station): its
## defence and repair jobs, well paid.

const NOTICE := 20000.0          # m: crimes a station sees
const FINE_ASSAULT := 250        # dr: firing on a trader or a patrol
const WANTED_TIME := 900.0       # s: the stations' guns on you after murder
const GUN_RANGE := 4500.0        # m
const GUN_EVERY := 0.55          # s a turret
const GUN_DAMAGE := 48.0         # (at you: a few seconds under them is death)
const GUN_DAMAGE_NPC := 14.0     # (at invaders, raiders)
const SIEGE_HIT := 0.12          # % of a station's condition an invader's hit takes
const INVADERS := 5              # ships of a fleet out at once
const HAIL_NEAR := 30000.0       # m

var cosmos: Node
var _gun_cd := {}                # turret -> s
var _hailed := {}                # station id -> true (this visit to the system)
var _tick := 0.0
var _burn := 0.0
var _fined_at := {}              # ship -> time (one fine a few seconds)
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## This system's record: {"debt": dr, "wanted": s left}.
func rec(sys := "") -> Dictionary:
	var all: Dictionary = CosmosGame.extra.get("crime", {})
	if not CosmosGame.extra.has("crime"):
		CosmosGame.extra["crime"] = all
	var id: String = sys if sys != "" else str(cosmos.system_id)
	if not all.has(id):
		all[id] = {"debt": 0, "wanted": 0.0}
	return all[id]


func wanted() -> bool:
	return float(rec().get("wanted", 0.0)) > 0.0


func debt() -> int:
	return int(rec().get("debt", 0))


## The station that saw it (the nearest within NOTICE), or null.
func _witness(p: Vector3) -> CosmosStation:
	var best: CosmosStation = null
	for st: CosmosStation in cosmos.stations:
		if st.global_position.distance_to(p) < NOTICE and (best == null or st.global_position.distance_to(p) < best.global_position.distance_to(p)):
			best = st
	return best


## Your bolt hitting `t` (a ship): a crime if it's a trader or a patrol not at war with you.
func player_hit(t: Node) -> void:
	if not t is CosmosNpcShip:
		return
	var s := t as CosmosNpcShip
	s.set_meta("by_player", true)
	if s.kind in ["pirate", "invader"] or Galaxy.is_hostile_to_player(s.faction):
		return
	var st := _witness(s.global_position)
	if st == null:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_fined_at.get(s, -99.0)) < 4.0:
		return
	_fined_at[s] = now
	_fine(st, FINE_ASSAULT, "firing on a %s" % ("patrol" if s.kind == "patrol" else "trader"))


func _fine(st: CosmosStation, amount: int, why: String) -> void:
	var data = CosmosGame.data
	var paid := mini(amount, int(data.credits))
	if paid > 0:
		data.add_credits(-paid)
	var r := rec()
	r["debt"] = int(r["debt"]) + amount - paid
	var who := str(cosmos.label_of(st))
	cosmos.hud.flash("%s: fined %d dr for %s%s" % [who, amount, why, (" - %d dr owed" % int(r["debt"])) if int(r["debt"]) > 0 else ""], 4.0)
	GameLog.post("Fined %d dr by %s for %s" % [amount, who, why], "danger")
	Galaxy.change_reputation(str(st.record.get("empire", "")), -2.0, why)


## One of theirs destroyed: by you (it had your bolts in it) - murder.
func ship_destroyed(s: CosmosNpcShip) -> void:
	if s.kind == "invader":
		var fleet := str(s.get_meta("fleet", ""))
		CosmosGame.missions.on_enemy_killed("warship", s.faction, fleet)
		if fleet != "":
			Fleets.ship_lost(fleet)
		if s.has_meta("by_player"):
			var b := 300 + _rng.randi_range(0, 200)
			CosmosGame.data.add_credits(b)
			var home := s.home as CosmosStation
			if home and is_instance_valid(home):
				Galaxy.change_reputation(str(home.record.get("empire", "")), 4.0, "defence")
			cosmos.hud.flash("%s destroyed - %d dr from the defenders" % [s.label, b], 3.0)
		return
	if not s.has_meta("by_player") or s.kind == "pirate" or Galaxy.is_hostile_to_player(s.faction):
		return
	var st := _witness(s.global_position)
	if st:
		_murder(st, "destroying a %s" % ("patrol" if s.kind == "patrol" else "trader"))


## Firing on a station: war if you're at war with it (or on a strike mission
## against it) - it takes the damage; else murder all the same.
func station_hit(st: CosmosStation, dmg: float) -> void:
	var sid := str(st.record.get("id", ""))
	var emp := str(st.record.get("empire", ""))
	var striking: bool = CosmosGame.missions.active.any(func(m): return m.get("type", "") == "strike" and m.get("station_id", "") == sid)
	if striking or Galaxy.is_hostile_to_player(emp):
		var pct := dmg * 0.01
		Galaxy.damage_station(sid, pct)
		CosmosGame.missions.on_station_hit(sid, pct)
	if not wanted():
		_murder(st, "firing on the station")


func _murder(st: CosmosStation, why: String) -> void:
	var r := rec()
	var first := float(r.get("wanted", 0.0)) <= 0.0
	r["wanted"] = WANTED_TIME
	var emp := str(st.record.get("empire", ""))
	if first:
		Galaxy.change_reputation(emp, -30.0, why)
		cosmos.hud.flash("WANTED for %s - the stations of %s will open fire on you" % [why, Galaxy.system(cosmos.system_id).get("name", "this system")], 6.0)
		GameLog.post("Wanted in %s for %s: its stations' guns are turned on you" % [Galaxy.system(cosmos.system_id).get("name", "?"), why], "danger")
	for x in cosmos.npc_ships:
		if is_instance_valid(x) and x.kind == "patrol":
			x.hostile = true


## Your ship lost: the law's done with you here.
func ship_lost() -> void:
	var r := rec()
	r["wanted"] = 0.0
	r["debt"] = 0


## Why `st` won't give you a pad ("" - it will). A debt you can pay is paid.
func refuses(st: CosmosStation) -> String:
	if wanted():
		return "%s refuses you - you're wanted here" % cosmos.label_of(st)
	if Galaxy.is_hostile_to_player(str(st.record.get("empire", ""))):
		return "%s refuses you - its empire counts you an enemy" % cosmos.label_of(st)
	var d := debt()
	if d > 0:
		if int(CosmosGame.data.credits) >= d:
			CosmosGame.data.add_credits(-d)
			rec()["debt"] = 0
			cosmos.hud.flash("Fine paid: %d dr" % d, 3.0)
			return ""
		return "%s refuses you - pay your fine first (%d dr)" % [cosmos.label_of(st), d]
	return ""


## Your bolt from `a` to `b`: into a station's parts? (it hit; true)
func player_bolt(a: Vector3, b: Vector3, dmg: float) -> bool:
	for st: CosmosStation in cosmos.stations:
		if st.global_position.distance_to(a) > st.reach + 200.0:
			continue
		var L := a.distance_to(b)
		if st.cam_hit(a, (b - a) / maxf(L, 0.001), L) < L:
			station_hit(st, dmg)
			return true
	return false


## An invader's bolt (aimed at a point of its station: meta "st", "aim"): there? (true: hit)
func invader_bolt(bolt: Node3D, a: Vector3, b: Vector3) -> bool:
	var st = bolt.get_meta("st", null)
	if st == null or not is_instance_valid(st):
		return true
	var p: Vector3 = (st as CosmosStation).to_global(bolt.get_meta("aim"))
	var seg := b - a
	var t := clampf((p - a).dot(seg) / maxf(seg.length_squared(), 0.0001), 0.0, 1.0)
	if (a + seg * t).distance_to(p) < 30.0:
		Galaxy.damage_station(str(st.record.get("id", "")), SIEGE_HIT)
		if a.distance_to(cosmos.focus().global_position) < 9000.0:
			CosmosBoom.at(cosmos, p, 10.0)
		return true
	return false


## A point on `st` to aim at (one of its parts, station space).
func station_point(st: CosmosStation) -> Vector3:
	var list: Array = st._solids
	for k in 6:
		var s: Array = list[_rng.randi() % list.size()]
		if not s[0]:
			return s[1]
	return Vector3.ZERO


# --- Each frame: the guns; a few times a second: sieges, hails, fires --------------

func _process(delta: float) -> void:
	if cosmos == null or not cosmos.built or get_tree().paused:
		return
	var r := rec()
	if float(r["wanted"]) > 0.0:
		r["wanted"] = maxf(0.0, float(r["wanted"]) - delta)
	_guns(delta)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 1.0
		_sieges()
		_hails()
	_burn -= delta
	if _burn <= 0.0:
		_burn = _rng.randf_range(0.6, 1.6)
		_fires()


## The turrets: each on the nearest thing it's to fire at, within GUN_RANGE -
## you (wanted; an enemy's station), invaders, raiders.
func _guns(delta: float) -> void:
	var me: Node3D = cosmos.ship
	var at_me: bool = me.state == "fly" and cosmos.walker == null and not cosmos.docked
	for st: CosmosStation in cosmos.stations:
		if st.turrets.is_empty() or st.global_position.distance_to(cosmos.focus().global_position) > st.reach + GUN_RANGE * 2.0:
			continue
		var hate_me := at_me and (wanted() or Galaxy.is_hostile_to_player(str(st.record.get("empire", ""))))
		var foes: Array = []
		for x in cosmos.npc_ships:
			if is_instance_valid(x) and not x.dead and (x.kind in ["invader", "pirate"]) and x.global_position.distance_to(st.global_position) < st.reach + GUN_RANGE:
				foes.append(x)
		if not hate_me and foes.is_empty():
			continue
		for tu: Node3D in st.turrets:
			var head: Node3D = tu.get_child(1)
			var muzzle := head.global_position
			var best: Node3D = null
			var bd := GUN_RANGE
			if hate_me and muzzle.distance_to(me.global_position) < bd:
				best = me
				bd = muzzle.distance_to(me.global_position) * 0.7   # (you first)
			for x in foes:
				var d := muzzle.distance_to(x.global_position)
				if d < bd:
					best = x
					bd = d
			if best == null:
				continue
			var d := muzzle.distance_to(best.global_position)
			var v: Vector3 = best.get("velocity") if best.get("velocity") != null else Vector3.ZERO
			var lead: Vector3 = best.global_position + v * (d / CosmosBolt.SPACE_SPEED)
			var up := st.global_basis.y
			if (lead - muzzle).normalized().dot(up) < -0.2:
				continue   # (below its deck: out of its arc)
			head.look_at(lead, up if absf((lead - muzzle).normalized().dot(up)) < 0.98 else st.global_basis.x)
			var cd := float(_gun_cd.get(tu, _rng.randf() * GUN_EVERY)) - delta
			if cd <= 0.0:
				cd = GUN_EVERY * _rng.randf_range(0.8, 1.3)
				var spread := 0.004
				var aim := (lead - muzzle).normalized() + Vector3(_rng.randfn(0, spread), _rng.randfn(0, spread), _rng.randfn(0, spread))
				var bolt := CosmosBolt.fire(cosmos, muzzle - head.global_basis.z * 9.0, aim, "enemy" if best == me else "station",
					GUN_DAMAGE if best == me else GUN_DAMAGE_NPC, true)
				bolt.big = true
			_gun_cd[tu] = cd


## The fleets besieging this system: their ships out round the station they're at.
func _sieges() -> void:
	if cosmos.docked or cosmos.walker:
		return
	var sys := str(cosmos.system_id)
	for f in Fleets.in_system(sys):
		if f["mission"] != "invade" or not (f["route"] as Array).is_empty() or f.get("waiting", false):
			continue
		var emp := str(f["empire"])
		# (its target: the weakest station here of an empire it's at war with)
		var target: CosmosStation = null
		for st: CosmosStation in cosmos.stations:
			if Galaxy.at_war(emp, Galaxy.station_owner(str(st.record.get("id", "")))):
				if target == null or Galaxy.station_health(str(st.record.get("id", ""))) < Galaxy.station_health(str(target.record.get("id", ""))):
					target = st
		if target == null or target.global_position.distance_to(cosmos.ship.global_position) > 60000.0:
			continue
		var out: Array = cosmos.npc_ships.filter(func(x): return is_instance_valid(x) and x.kind == "invader" and str(x.get_meta("fleet", "")) == str(f["id"]))
		if out.size() >= mini(int(f["size"]), INVADERS) or not CosmosHull.ready("patrol", emp):
			continue
		var s := CosmosNpcShip.new()
		s.setup("invader", cosmos, _rng.randi(), emp)
		s.set_meta("fleet", str(f["id"]))
		s.home = target
		cosmos.world.add_child(s)
		var dir := Vector3(_rng.randfn(), _rng.randfn() * 0.2, _rng.randfn()).normalized()
		s.global_position = target.global_position + dir * (target.reach + 5000.0)
		s.look_at(target.global_position, Vector3.UP)
		cosmos.npc_ships.append(s)


## A station burning or besieged hails you as you come near: its jobs.
func _hails() -> void:
	if cosmos.docked or cosmos.walker or cosmos.get_tree().paused or cosmos.ship.state != "fly":
		return
	for st: CosmosStation in cosmos.stations:
		var sid := str(st.record.get("id", ""))
		if _hailed.has(sid) or st.global_position.distance_to(cosmos.ship.global_position) > HAIL_NEAR:
			continue
		var hurt := Galaxy.station_health(sid) < Galaxy.DAMAGED
		var siege := Fleets.besieged(sid)
		if not (hurt or siege) or Galaxy.is_hostile_to_player(str(st.record.get("empire", ""))) or wanted():
			continue
		_hailed[sid] = true
		cosmos.hail_station(st, siege)
		return


## Explosions on stations that are hurt (more the worse they are), near you.
func _fires() -> void:
	var f: Vector3 = cosmos.focus().global_position
	for st: CosmosStation in cosmos.stations:
		var h := Galaxy.station_health(str(st.record.get("id", "")))
		if h >= 95.0 or st.global_position.distance_to(f) > st.reach + 12000.0 or st._solids.is_empty():
			continue
		if _rng.randf() > (100.0 - h) / 60.0:
			continue
		var p := st.to_global(station_point(st))
		CosmosBoom.at(cosmos, p, _rng.randf_range(8.0, 22.0) * (1.6 if h < Galaxy.DAMAGED else 1.0))


## Leaving the system: the next visit's hails anew.
func new_system() -> void:
	_hailed.clear()
	_gun_cd.clear()
	_fined_at.clear()
