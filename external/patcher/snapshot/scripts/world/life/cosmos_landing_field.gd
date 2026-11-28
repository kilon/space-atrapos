class_name CosmosLandingField
extends Node
## The towns' landing pads and their traffic (the 3D game; a child of Cosmos).
##   The pads - beside a city's landing field, on the levelled ground at the
##     town's edge: 3-6 a city (by its seed), 0-1 a village. Big pads (a
##     shuttle's: its length + 4 m by 27 m) two rows each side of the field, a
##     courier's small one (24 m) past them; each in its empire's look
##     (EmpireKit: its paint, the hazard band, the roundel with its emblem, a
##     chevron at its nose end), lamps round its edges lit by night (the town
##     shader's lamp slot, as the streets' lamps), and a control tower at the
##     field's far end with its beacon. One mesh (and one of lamps) a town,
##     built on a worker when its town is; their solids added to the town's
##     (walked on, the camera's obstacles).
##   The traffic - each pad's rounds (CYCLE s): in most a ship comes down on it
##     (a shuttle - local traders and the pilots' own - or a courier's skiff,
##     the empire's EmpireHulls designs), sits a few minutes and lifts off. Its
##     schedule is a function of the galaxy's clock and the pad (slot): far
##     from you it's only those numbers; within NEAR m the ship's there, flown
##     here (fly: in from the sky, down onto the pad, its ramp down; up, away
##     and gone). A pad is one ship's at a time; none come down on one your ship
##     is on; one hired off it (CosmosSandbox) leaves it free for that round.
##   Its pilot - when it's down near you, a named pilot walks down its ramp
##     (CosmosNpc.leave_ship) into the town - its square, a house's door, the
##     palace's colonnade - stays there, walks back and up the ramp before it
##     lifts off. Talk to him for a ride (CosmosSandbox: this system's stations,
##     a town on another world, systems through the gates - a price each).
## Saved: only the rounds taken by a hire (CosmosGame.extra "pads_taken");
## the rest comes back from the clock - a ship mid-stay is there again, its pilot ashore.
##   CosmosLandingField.of(cosmos)

const CLASS := "res://scripts/world/life/cosmos_landing_field.gd"
const NEAR := 2600.0            # m: a pad's ship flown within this of you
const GONE := 3200.0            # ...and back to numbers past this
const ASHORE := 420.0           # m: its pilot out in the town within this (the town's people's reach)
const SIM_HZ := 4.0
const CYCLE := 420.0            # s: a pad's round
const APPROACH := 34.0          # s: from the sky down onto it
const LIFT := 26.0              # s: off it and gone
const STAY := [150.0, 260.0]    # s down on it
const BUSY := 0.72              # of the rounds a ship comes
const DECK := 0.12              # m: the pads' decks over the ground
const ROW_W := 27.0             # m: a big pad's width (along the field's edge)
const SMALL := 24.0
const TOWER := Vector3(40.0, 0.0, 0.0)   # (from the field's middle: its far end)
const PEOPLE := {"minoa": "Minoans", "athens": "Athenians", "sparta": "Spartans", "mycenae": "Mycenaeans", "ionia": "Ionians", "cyclades": "Islanders"}
const EMPS := ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades"]

var cosmos: Node
var live := {}                  # pad key -> {ship, pilot, slot, town, pad, state, t, near}
var _sim_t := 0.0
var _jobs := {}                 # town -> [job, result]
static var test_busy := -1.0    # (tests: every round busy (1) or none (0))


static func of(c: Node) -> Node:
	var n := c.get_node_or_null("LandingField")
	if n == null:
		n = load(CLASS).new()
		n.name = "LandingField"
		n.set("cosmos", c)
		c.add_child(n)
	return n


# --- The pads -----------------------------------------------------------------------------

## A town's pads (town-local, y up): [{id, at (its deck's middle, on top), size (x along the
## town's x - a ship's length - , y along z), big}]. Only those on its levelled ground.
static func pads_of(site: Dictionary) -> Array:
	var kind := str(site.get("kind", "village"))
	var lay := CosmosTown.layout(kind)
	var half: float = lay["half"]
	var port: Vector3 = lay["port"]
	var r: float = float(site.get("r", 130.0))
	var emp := str(site.get("empire", ""))
	var length := CosmosHull.size_of("shuttle", emp) * 22.0 + 4.0
	var x0 := half + 12.0   # (room between the town's edge and a ship's stern for its ramp, and a way along it)
	var out: Array = []
	var seed := int(site.get("seed", 0))
	var want := (3 + absi(seed) % 4) if kind == "city" else (absi(seed / 7) % 2)
	for spec in [[0, -1.0], [0, 1.0], [1, -1.0], [1, 1.0], [2, -1.0], [2, 1.0]]:
		if out.size() >= want:
			break
		var row: int = spec[0]
		var big := row < 2
		var w := ROW_W if big else SMALL
		var l := length if big else SMALL
		var z0 := port.z + 37.0 + row * 29.0   # (clear of the field's stone and its lamps; 2 m between)
		var c := Vector3(x0 + l * 0.5, DECK, float(spec[1]) * (z0 + w * 0.5))
		var far := Vector2(c.x + l * 0.5, absf(c.z) + w * 0.5).length()
		if far > r - 1.0:
			continue   # (off its levelled ground)
		out.append({"id": out.size() + 1, "at": c, "size": Vector2(l, w), "big": big})
	return out


## The control tower's place (town-local), or null if it's off the level ground.
static func tower_of(site: Dictionary) -> Variant:
	var lay := CosmosTown.layout(str(site.get("kind", "village")))
	var at: Vector3 = (lay["port"] as Vector3) + TOWER
	if at.length() + 4.5 > float(site.get("r", 130.0)):
		return null
	return at


## A ship on pad `p` (town-local): its deck's middle, the ship's frame - its nose out along the town's x.
static func pad_frame(p: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0)), p["at"])


static func key_of(pl: Node, site: Dictionary, p: Dictionary) -> String:
	return "%s:%s|%d" % [str(pl.rec.get("id", "")) if pl else "", str(site.get("name", "")), int(p["id"])]


# --- The schedule -------------------------------------------------------------------------

## Pad `p`'s round `c` (key: key_of): {busy, c, arrive, land, leave, gone (galaxy time), kind
## (shuttle, trader, courier), hull, empire, seed, pilot (his name), emp_pilot}.
static func slot(key: String, p: Dictionary, c: int, town_emp: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s#%d" % [key, c])
	var phase := float(absi(hash(key)) % int(CYCLE))
	var start := c * CYCLE + phase
	var busy := rng.randf() < BUSY
	if test_busy >= 0.0:
		busy = test_busy > 0.5
	var taken: Dictionary = CosmosGame.extra.get("pads_taken", {})
	if int(taken.get(key, -999)) == c:
		busy = false   # (its ship hired off it this round)
	var arrive := start + rng.randf_range(0.0, 50.0)
	var land := arrive + APPROACH
	var leave := land + rng.randf_range(STAY[0], STAY[1])
	var kind := "courier"
	if p["big"]:
		var k := rng.randf()
		kind = "shuttle" if k < 0.55 else ("trader" if k < 0.88 else "courier")
	var emp: String = town_emp if rng.randf() < 0.75 or not town_emp in EMPS else str(EMPS[rng.randi() % EMPS.size()])
	var given: String = People.GIVEN[rng.randi() % People.GIVEN.size()]
	var family: String = People.FAMILY[rng.randi() % People.FAMILY.size()]
	return {"busy": busy, "c": c, "arrive": arrive, "land": land, "leave": leave, "gone": leave + LIFT, "kind": kind,
		"hull": "fighter" if kind == "courier" else "shuttle", "empire": emp, "seed": rng.randi(), "pilot": "%s %s" % [given, family]}


## The round of pad `p` going on at galaxy time `time`.
static func slot_at(key: String, p: Dictionary, time: float, town_emp: String) -> Dictionary:
	var phase := float(absi(hash(key)) % int(CYCLE))
	return slot(key, p, floori((time - phase) / CYCLE), town_emp)


## The next round (from `time` on) a ship comes down on pad `p`.
static func next_busy(key: String, p: Dictionary, time: float, town_emp: String) -> Dictionary:
	var phase := float(absi(hash(key)) % int(CYCLE))
	var c := floori((time - phase) / CYCLE)
	for i in 40:
		var s := slot(key, p, c + i, town_emp)
		if s["busy"] and float(s["arrive"]) >= time:
			return s
	return {}


# --- Each frame ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if cosmos == null or not cosmos.get("planets"):
		return
	_sim_t += delta
	if _sim_t < 1.0 / SIM_HZ:
		return
	_sim_t = 0.0
	_meshes()
	tick()


## (Shots, the tour) A ship on pad `p` of `t` now, `since` s after it set out to come down
## (APPROACH: on the pad; more: its pilot out) - its round moved to now.
func stage(t: CosmosTown, p: Dictionary, since: float, kind := "shuttle") -> CosmosNpcShip:
	var key := key_of(t.planet, t.site, p)
	_drop(key)
	var s := slot_at(key, p, Galaxy.time, str(t.site.get("empire", ""))).duplicate()
	var shift := Galaxy.time - since - float(s["arrive"])
	for k in ["arrive", "land", "leave", "gone"]:
		s[k] = float(s[k]) + shift
	s["busy"] = true
	s["kind"] = kind if p["big"] else "courier"
	s["hull"] = "fighter" if s["kind"] == "courier" else "shuttle"
	_launch(key, t, p, s, Galaxy.time)
	return live[key]["ship"] if live.has(key) else null


## The towns near you: their pads' rounds looked at - a ship put in where one's due, taken out past GONE.
func tick() -> void:
	var f: Node3D = cosmos.focus() if cosmos.has_method("focus") else null
	if f == null:
		return
	var at := f.global_position
	var now: float = Galaxy.time
	var seen := {}
	for t in _towns():
		var town: CosmosTown = t
		var d := town.global_position.distance_to(at)
		if d > GONE:
			continue
		var emp := str(town.site.get("empire", ""))
		for p in pads_of(town.site):
			var key := key_of(town.planet, town.site, p)
			seen[key] = true
			if live.has(key):
				_watch(key, d)
				continue
			if d > NEAR:
				continue
			var s := slot_at(key, p, now, emp)
			if not s["busy"] or now < float(s["arrive"]) or now >= float(s["gone"]):
				continue
			if not CosmosHull.ready(str(s["hull"]), str(s["empire"])):
				continue   # (its design still being made: next time)
			if _blocked(town, p):
				_take(key, int(s["c"]))   # (your ship's on it: this round it goes elsewhere)
				continue
			_launch(key, town, p, s, now)
	for key in live.keys():
		if not seen.has(key):
			_drop(key)
	var taken: Dictionary = CosmosGame.extra.get("pads_taken", {})
	if taken.size() > 24:   # (old rounds forgotten)
		for k in taken.keys():
			if not live.has(k):
				taken.erase(k)


func _towns() -> Array:
	var out: Array = []
	var tw = cosmos.get("_towns")
	if tw == null:
		return out
	for list in tw.values():
		for t in list:
			if t != null and is_instance_valid(t) and t.is_inside_tree():
				out.append(t)
	return out


## Your ship on (or over) pad `p` of `t`.
func _blocked(t: CosmosTown, p: Dictionary) -> bool:
	var sh: Node3D = cosmos.get("ship")
	if sh == null or not sh.visible or cosmos.get("ship_elsewhere"):
		return false
	var l := t.to_local(sh.global_position)
	var sz: Vector2 = p["size"]
	var c: Vector3 = p["at"]
	return absf(l.x - c.x) < sz.x * 0.5 + 8.0 and absf(l.z - c.z) < sz.y * 0.5 + 8.0 and l.y < 400.0


func _take(key: String, c: int) -> void:
	var taken: Dictionary = CosmosGame.extra.get("pads_taken", {})
	taken[key] = c
	CosmosGame.extra["pads_taken"] = taken


## A pad's ship flown: in the sky on its way down, down on it, or on its way up - where its round has it now.
func _launch(key: String, t: CosmosTown, p: Dictionary, s: Dictionary, now: float) -> void:
	var sh := CosmosNpcShip.new()
	sh.setup("trader", cosmos, int(s["seed"]), str(s["empire"]), str(s["hull"]))
	var short := str(Galaxy.EMPIRES.get(str(s["empire"]), {}).get("short", "Independent"))
	var what := str(s["kind"])
	sh.label = "%s %s - %s" % [short, what, s["pilot"]]
	sh.name = "FieldShip"
	sh.set_meta("field_key", key)
	sh.set("traffic", self)
	cosmos.world.add_child(sh)
	cosmos.npc_ships.append(sh)
	sh._make_gear()
	var r := {"ship": sh, "pilot": null, "slot": s, "town": t, "pad": p, "state": "in", "t": 0.0, "near": false}
	live[key] = r
	if now >= float(s["leave"]):
		r["state"] = "up"   # (its pilot back aboard already: lifting off)
		r["t"] = now - float(s["leave"])
	elif now >= float(s["land"]):
		r["state"] = "down"
		r["t"] = now - float(s["land"])
		sh._gear_k = 1.0
		sh._ramp_k = 1.0
		sh._gear_show()
		r["ashore"] = r["t"] > 12.0   # (down a while: its pilot's in the town already)
	fly(sh, 0.0)


## Gone back to numbers (its town far, or gone): the ship and its pilot taken out.
func _drop(key: String) -> void:
	var r: Dictionary = live.get(key, {})
	live.erase(key)
	if r.is_empty():
		return
	var s = r["ship"]
	if is_instance_valid(s) and s.get("traffic") == self:
		cosmos.npc_ships.erase(s)
		s.queue_free()
	_free_pilot(r)


func _free_pilot(r: Dictionary) -> void:
	var x = r.get("pilot")
	r["pilot"] = null
	if is_instance_valid(x) and x.get("ride") == null:
		cosmos.citizens.erase(x)
		x.queue_free()


## Each tick, a pad's ship that's here: its pilot out (near, the ramp down) or back, hired off, gone.
func _watch(key: String, d: float) -> void:
	var r: Dictionary = live[key]
	var s: CosmosNpcShip = r["ship"] if is_instance_valid(r["ship"]) else null
	if s == null:
		live.erase(key)   # (shot down, or gone)
		_free_pilot(r)
		return
	if r["state"] == "hired":
		# (its pilot's yours now: the pad its until it's off it - then free this round)
		if s.hire.is_empty() or not s.hire_state() in ["wait", "climb"]:
			live.erase(key)
		return
	var t: CosmosTown = r["town"]
	var x = r["pilot"]
	if r["state"] == "down" and d < ASHORE and t.built and s._ramp_k > 0.99 and not is_instance_valid(x) and not r.get("back", false):
		_pilot_out(r, bool(r.get("ashore", false)) or float(r["t"]) > 20.0)   # (down a while before you came near: he's in the town)
	elif is_instance_valid(x) and d > ASHORE * 1.5 and x.get("_off") == 2:
		_free_pilot(r)   # (out of the town's reach: one of its numbers again)
		r["ashore"] = true
	if r["state"] == "down" and Galaxy.time >= float((r["slot"] as Dictionary)["leave"]):
		r["state"] = "call"   # (its time up: its pilot back to it)
		r["t"] = 0.0
		if is_instance_valid(r["pilot"]):
			r["pilot"].call("go_back")


## Its pilot out: down its ramp (or, it's been down a while, already in the town).
func _pilot_out(r: Dictionary, ashore: bool) -> void:
	var t: CosmosTown = r["town"]
	var s: CosmosNpcShip = r["ship"]
	var sl: Dictionary = r["slot"]
	var x := CosmosNpc.new()
	x.cosmos = cosmos
	x.citizen_of(t, int(sl["seed"]), "pilot")
	x.role = "captain"
	x.label = "%s, pilot of the %s" % [sl["pilot"], str(s.label).get_slice(" - ", 0)]
	x.name = "FieldPilot"
	x.set_meta("field_key", key_of(t.planet, t.site, r["pad"]))
	x.set_meta("courier", sl["kind"] == "courier")
	x.set_meta("who", str(sl["pilot"]))
	x.set_meta("pad", int((r["pad"] as Dictionary)["id"]))
	x.stay_at = _stay_spot(t, int(sl["seed"]))
	cosmos.world.add_child(x)
	cosmos.citizens.append(x)
	r["pilot"] = x
	if s.interior == null and not ashore:
		s.make_interior()   # (its doorway cut in its hull, its insides made on a worker)
	if ashore:
		x.leave_ship(s, true)
	else:
		x.leave_ship(s)


## Where a pilot spends his time ashore (town-local): the square (open ground near its
## middle), a house's door, the palace's colonnade.
static func _stay_spot(t: CosmosTown, seed: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var k := rng.randf()
	if str(t.site.get("kind", "")) == "city" and k < 0.3:
		return Vector3(-16.6, 0.0, rng.randf_range(-8.0, 8.0))   # (the colonnade before the palace's west wing)
	if k < 0.6 and not t.doors.is_empty():
		var dr: Array = t.doors[rng.randi() % t.doors.size()]
		return (dr[0] as Vector3) + (dr[1] as Vector3) * 1.4
	if t.spots.is_empty():
		return t.port + Vector3(-30.0, 0, 0)
	var near: Array = t.spots.duplicate()
	near.sort_custom(func(a, b): return Vector2(a.x, a.z).length() < Vector2(b.x, b.z).length())
	var p: Vector3 = near[rng.randi() % mini(12, near.size())]
	return Vector3(p.x, 0.0, p.z)


# --- Flying them --------------------------------------------------------------------------

## A pad's ship, each frame (CosmosNpcShip._process): where its round has it.
func fly(s: CosmosNpcShip, delta: float) -> void:
	var key := str(s.get_meta("field_key", ""))
	var r: Dictionary = live.get(key, {})
	if r.is_empty() or not is_instance_valid(r["town"]) or r["ship"] != s:
		s.set("traffic", null)
		cosmos.npc_ships.erase(s)
		s.queue_free()
		return
	var t: CosmosTown = r["town"]
	var p: Dictionary = r["pad"]
	var sl: Dictionary = r["slot"]
	var deck := t.global_transform * pad_frame(p)
	var rest := Transform3D(deck.basis, deck.origin + deck.basis.y * s.rest_height())
	var u := deck.basis.y
	var out := t.global_basis.x.normalized()
	match str(r["state"]):
		"in":   # (from the sky: in over the town's far side, slowing, down onto the pad)
			var k := clampf((Galaxy.time - float(sl["arrive"])) / APPROACH, 0.0, 1.0)
			var from := rest.origin + u * 1500.0 + out * 2600.0
			var over := rest.origin + u * 90.0
			var bend := rest.origin + u * 520.0 + out * 380.0
			if k < 0.72:
				var q := k / 0.72
				q = 1.0 - (1.0 - q) * (1.0 - q)   # (fast in, slowing)
				var a := from.lerp(bend, q)
				var b := bend.lerp(over, q)
				var p0 := a.lerp(b, q)
				var go := (b - a)
				if go.length() > 0.01:
					s.global_basis = s.global_basis.slerp(Cosmos._level(go.normalized(), u), minf(1.0, maxf(delta, 0.02) * 2.0)).orthonormalized() if delta > 0.0 else Cosmos._level(go.normalized(), u)
				s.global_position = p0
				s._gear_step(0.0, 0.0, delta)
			else:
				var q := smoothstep(0.0, 1.0, (k - 0.72) / 0.28)
				s.global_position = over.lerp(rest.origin, q)
				s.global_basis = s.global_basis.slerp(rest.basis, minf(1.0, maxf(delta, 0.02) * 1.6)).orthonormalized() if delta > 0.0 else rest.basis
				s._gear_step(1.0 if q > 0.35 else 0.0, 0.0, delta)
			s._engines_glow(0.8)
			if k >= 1.0:
				s.global_transform = rest
				r["state"] = "down"
				r["t"] = 0.0
				_note(r, "lands at")
		"down", "call":   # (on the pad, its ramp down: its pilot off into the town, back)
			r["t"] = float(r["t"]) + delta
			s.global_transform = rest
			s._gear_step(1.0, 1.0 if float(r["t"]) > 1.5 or r["state"] == "call" else 0.0, delta)
			s._engines_glow(0.0)
			if r["state"] == "call":
				var x = r["pilot"]
				var aboard: bool = not is_instance_valid(x) or x.get("_off") == 5
				var w: Node = cosmos.get("walker")
				if w and s.interior and w.get("deck") == s.interior:
					r["t"] = minf(float(r["t"]), 140.0)   # (you aboard, walking round it: it waits till you're down its ramp)
				elif aboard or float(r["t"]) > 150.0:   # (back aboard - or never coming: off without him)
					_free_pilot(r)
					r["state"] = "up"
					r["t"] = 0.0
		"up":   # (its ramp up, its legs in once it's off the deck; straight up, then away, climbing)
			r["t"] = float(r["t"]) + delta
			var tt: float = r["t"]
			s._gear_step(1.0 if tt < 4.0 else 0.0, 0.0, delta)
			var h := 0.0
			var o := 0.0
			if tt > 3.0:
				var v := tt - 3.0
				h = minf(v, 8.0) * minf(v, 8.0) * 1.9
				if v > 8.0:
					var w := v - 8.0
					h += 30.0 * w + 6.0 * w * w
					o = 10.0 * w * w
			var p1 := rest.origin + u * h + out * o
			var go := p1 - s.global_position
			if o > 1.0 and go.length() > 0.01:
				s.global_basis = s.global_basis.slerp(Cosmos._level(go.normalized(), u), minf(1.0, maxf(delta, 0.02) * 0.8)).orthonormalized()
			elif o <= 1.0:
				s.global_basis = rest.basis
			s.global_position = p1
			s._engines_glow(0.8 if tt > 2.5 else 0.0)
			if tt > 3.0 and not r.get("off_noted", false):
				r["off_noted"] = true
				_note(r, "lifts off from")
			if tt >= LIFT:
				live.erase(key)
				s.set("traffic", null)
				cosmos.npc_ships.erase(s)
				s.queue_free()


## The event log: what you see come and go (only the ships near you - flown).
func _note(r: Dictionary, verb: String) -> void:
	var t: CosmosTown = r["town"]
	if cosmos and cosmos.has_method("within_news") and is_instance_valid(t) and not cosmos.within_news(t.global_position):
		return   # (a far town's field: not news - only within 2 km of you)
	var sl: Dictionary = r["slot"]
	var what: String = "A " + str(sl["kind"])
	var who := str(PEOPLE.get(str(sl["empire"]), "Independents"))
	var text := "%s of the %s %s %s's field (pad %d)" % [what, who, verb, t.site.get("name", "the town"), int((r["pad"] as Dictionary)["id"])]
	GameLog.post(text, "info")


# --- Hired off its pad (CosmosSandbox) ----------------------------------------------------

## The pad's record of pilot `x` (or {}).
func record_of(x: Node) -> Dictionary:
	var key := str(x.get_meta("field_key", "")) if x else ""
	var r: Dictionary = live.get(key, {})
	return r if not r.is_empty() and r.get("pilot") == x else {}


## Pilot `x` hired to `to` (CosmosNpcShip.hire_ride's `to`): his ship no longer
## the field's - a hired ride waiting on its pad (CosmosNpcShip "wait": he walks back
## to it and up to its pilot's seat, you after him); the pad free once it's off.
func hire(x: Node, to: Dictionary) -> CosmosNpcShip:
	var r := record_of(x)
	if r.is_empty() or not is_instance_valid(r["ship"]):
		return null
	var s: CosmosNpcShip = r["ship"]
	var t: CosmosTown = r["town"]
	var key := key_of(t.planet, t.site, r["pad"])
	_take(key, int((r["slot"] as Dictionary)["c"]))
	s.set("traffic", null)
	s.make_interior()
	s.hire = {"state": "wait", "t": 0.0, "pl": t.planet, "field": t.transform * pad_frame(r["pad"]), "to": to, "pilot": x,
		"pilot_walk": x.global_position.distance_to(s.global_position) * 1.8 / CosmosNpc.CREW_RUN}   # (waited for while he walks back through the town)
	s.label = "%s's shuttle" % str(x.get_meta("who", "The pilot"))
	r["state"] = "hired"
	r["pilot"] = null   # (his own now: walking to it, aboard)
	x.call("go_back", true)
	return s


# --- Their meshes -------------------------------------------------------------------------

## Each built town's pads made (on a worker) and put in: its deck mesh, its lamps, its solids.
func _meshes() -> void:
	for t in _towns():
		var town: CosmosTown = t
		if not town.built:
			_jobs.erase(town)
			continue
		if town.has_node("LandingField"):
			var lf := town.get_node("LandingField")
			var lit := maxf(town.lit, 0.0)
			if absf(float(lf.get_meta("lit", -1.0)) - lit) > 0.004:
				lf.set_meta("lit", lit)
				for ch in lf.get_children():
					if ch.name == "Lamps":
						(ch as MeshInstance3D).set_instance_shader_parameter("lamp_lit", lit)
			continue
		var pads := pads_of(town.site)
		if pads.is_empty():
			continue
		if not _jobs.has(town):
			var site: Dictionary = town.site
			var job := {"out": {}}
			job["id"] = Jobs.add(func(): job["out"] = build(site), false, "landing pads")
			_jobs[town] = job
			continue
		var j: Dictionary = _jobs[town]
		if not Jobs.done(int(j["id"])):
			continue
		Jobs.wait(int(j["id"]))
		_jobs.erase(town)
		_put_in(town, j["out"])


func _exit_tree() -> void:
	for t in _jobs:
		Jobs.wait(int(_jobs[t]["id"]))   # (no worker left running)
	_jobs = {}


## A mesh from arrays made on a worker (here, on the main thread); a mesh as it is.
static func _mesh_of(a) -> Mesh:
	if a is Mesh:
		return a
	var m := ArrayMesh.new()
	if a is Array and not (a as Array).is_empty() and a[Mesh.ARRAY_VERTEX] != null and (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() > 0:
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


## The made meshes into the town (a node of their own) and their solids into its own.
static func _put_in(town: CosmosTown, out: Dictionary) -> void:
	var lf := Node3D.new()
	lf.name = "LandingField"
	var emp := str(town.site.get("empire", ""))
	var deck := MeshInstance3D.new()
	deck.name = "Pads"
	deck.mesh = _mesh_of(out["deck"])
	deck.material_override = EmpireKit.mat("hull", emp if EmpireKit.LOOKS.has(emp) else "")
	deck.visibility_range_end = 6000.0
	lf.add_child(deck)
	var lamps := MeshInstance3D.new()
	lamps.name = "Lamps"
	lamps.mesh = _mesh_of(out["lamps"])
	lamps.material_override = CosmosTown.material(emp)
	lamps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lamps.visibility_range_end = 6000.0
	var lit := maxf(town.lit, 0.0) if town.lit >= 0.0 else TownLamps.night_of(town)
	lamps.set_instance_shader_parameter("lamp_lit", lit)
	lf.set_meta("lit", lit)
	lf.add_child(lamps)
	town.add_child(lf)
	add_solids(town, out["solids"])


## Blocks added to a built town's solids (and its grid's cells).
static func add_solids(town: CosmosTown, solids: Array) -> void:
	for b in solids:
		var i := town._solids.size()
		town._solids.append(b)
		var a: AABB = b
		for gx in range(floori((a.position.x - 1.0) / CosmosSolids.GRID), floori((a.end.x + 1.0) / CosmosSolids.GRID) + 1):
			for gz in range(floori((a.position.z - 1.0) / CosmosSolids.GRID), floori((a.end.z + 1.0) / CosmosSolids.GRID) + 1):
				var k := Vector2i(gx, gz)
				var cell: PackedInt32Array = town._grid.get(k, PackedInt32Array())
				cell.append(i)
				town._grid[k] = cell


## A town's pads, made (a worker): {deck: mesh arrays (EmpireKit's zones), lamps: mesh arrays
## (the town shader's lamp slot), solids: [AABB]} - town-local.
static func build(site: Dictionary) -> Dictionary:
	var m := EmpireKit.Mesher.new()
	var L := _Lamps.new()
	var solids: Array = []
	for p in pads_of(site):
		var c: Vector3 = p["at"]
		var sz: Vector2 = p["size"]
		var hx := sz.x * 0.5
		var hz := sz.y * 0.5
		# The deck: a slab of the empire's paint, its kerb dark iron.
		m.boxat(Vector3(sz.x, DECK + 0.4, sz.y), Vector3(c.x, (DECK - 0.4) * 0.5, c.z), EmpireKit.MAIN)
		m.boxat(Vector3(sz.x + 0.6, 0.3, sz.y + 0.6), Vector3(c.x, -0.12, c.z), EmpireKit.IRON)
		var y := DECK + 0.012
		# The hazard band round it, a line of the accent inside it.
		for e in 4:
			var along_x := e < 2
			var sd := -1.0 if e % 2 == 0 else 1.0
			if along_x:
				_strip(m, Vector3(c.x, y, c.z + sd * (hz - 1.1)), Vector2(sz.x - 1.2, 1.0), EmpireKit.HAZARD)
				_strip(m, Vector3(c.x, y, c.z + sd * (hz - 2.6)), Vector2(sz.x - 4.2, 0.35), EmpireKit.ACCENT)
			else:
				_strip(m, Vector3(c.x + sd * (hx - 1.1), y, c.z), Vector2(1.0, sz.y - 4.2), EmpireKit.HAZARD)
				_strip(m, Vector3(c.x + sd * (hx - 2.6), y, c.z), Vector2(0.35, sz.y - 4.9), EmpireKit.ACCENT)
		# The roundel (its emblem) in its middle; a chevron at its nose end (the town's x: out).
		m.disc(Vector3(c.x, y + 0.006, c.z), Vector3.UP, Vector3(-1, 0, 0), minf(hx, hz) * 0.42, EmpireKit.ROUNDEL, 28)
		var nose := c.x + hx - 4.6
		for sd in [-1.0, 1.0]:
			var a := Vector3(nose, y + 0.004, c.z)
			var b := Vector3(nose - 2.6, y + 0.004, c.z + sd * 3.0)
			var dir := (b - a).normalized()
			var side := Vector3(-dir.z, 0, dir.x) * 0.45
			m.quad(a - side, b - side, b + side, a + side, EmpireKit.ACCENT, Vector3(c.x, -1.0, c.z))
		# Its lamps: a glowing line just in from each edge, a lamp in housings at its corners and along its sides.
		for e in 4:
			var along_x := e < 2
			var sd := -1.0 if e % 2 == 0 else 1.0
			if along_x:
				L.strip(Vector3(c.x, y + 0.004, c.z + sd * (hz - 0.3)), Vector2(sz.x - 0.6, 0.22))
			else:
				L.strip(Vector3(c.x + sd * (hx - 0.3), y + 0.004, c.z), Vector2(0.22, sz.y - 0.6))
		for ex in [-1.0, 1.0]:
			for ez in [-1.0, 1.0]:
				var q := Vector3(c.x + ex * (hx + 0.7), 0.0, c.z + ez * (hz + 0.7))
				m.boxat(Vector3(0.7, 0.36, 0.7), q + Vector3(0, 0.18, 0), EmpireKit.IRON)
				L.box(q + Vector3(0, 0.36, 0), Vector3(0.42, 0.2, 0.42))
		solids.append(AABB(Vector3(c.x - hx, -0.4, c.z - hz), Vector3(sz.x, DECK + 0.4, sz.y)))
	var tw = tower_of(site)
	if tw != null:
		_tower(m, L, tw as Vector3, solids)
	return {"deck": m.arrays(), "lamps": L.arrays(), "solids": solids}   # (arrays: their meshes made on the main thread - meshes made on workers race in the renderer)


## A flat band on the deck (its middle, its size x by z), facing up.
static func _strip(m: EmpireKit.Mesher, mid: Vector3, size: Vector2, zone: int) -> void:
	var hx := size.x * 0.5
	var hz := size.y * 0.5
	m.quad(mid + Vector3(-hx, 0, -hz), mid + Vector3(hx, 0, -hz), mid + Vector3(hx, 0, hz), mid + Vector3(-hx, 0, hz), zone, mid - Vector3.UP)


## The field's control tower at `at` (its foot): a plinth, a shaft (the roundel on it),
## the glazed cab (lit by night), its roof, the mast and its beacon.
static func _tower(m: EmpireKit.Mesher, L, at: Vector3, solids: Array) -> void:
	m.boxat(Vector3(6.4, 0.8, 6.4), at + Vector3(0, 0.4, 0), EmpireKit.IRON)
	m.boxat(Vector3(4.0, 8.6, 4.0), at + Vector3(0, 0.8 + 4.3, 0), EmpireKit.MAIN)
	m.boxat(Vector3(4.3, 0.5, 4.3), at + Vector3(0, 9.15, 0), EmpireKit.ACCENT)
	for sd in [-1.0, 1.0]:   # (the roundel toward the field and away)
		m.disc(at + Vector3(sd * 2.02, 5.2, 0), Vector3(sd, 0, 0), Vector3.UP, 1.5, EmpireKit.ROUNDEL, 24)
	m.boxat(Vector3(7.0, 0.4, 7.0), at + Vector3(0, 9.6, 0), EmpireKit.IRON)   # (the cab's floor)
	for ex in [-1.0, 1.0]:
		for ez in [-1.0, 1.0]:
			m.boxat(Vector3(0.35, 2.8, 0.35), at + Vector3(ex * 3.3, 11.2, ez * 3.3), EmpireKit.STEEL)
	m.boxat(Vector3(6.4, 0.6, 6.4), at + Vector3(0, 10.1, 0), EmpireKit.MAIN)   # (under its windows)
	L.box(at + Vector3(0, 11.4, 0), Vector3(6.3, 2.0, 6.3))   # (its windows: lit within by night)
	m.boxat(Vector3(7.6, 0.45, 7.6), at + Vector3(0, 12.8, 0), EmpireKit.ACCENT)   # (its roof)
	m.boxat(Vector3(7.8, 0.12, 7.8), at + Vector3(0, 13.08, 0), EmpireKit.GOLD)
	m.cyl(at + Vector3(0, 13.1, 0), at + Vector3(0, 17.0, 0), 0.14, 0.1, EmpireKit.STEEL, 8)
	m.boxat(Vector3(0.6, 0.6, 0.6), at + Vector3(0, 17.2, 0), EmpireKit.LAMP)   # (its beacon: always lit)
	solids.append(AABB(at - Vector3(3.2, 0, 3.2), Vector3(6.4, 0.8, 6.4)))
	solids.append(AABB(at + Vector3(-2.0, 0.8, -2.0), Vector3(4.0, 12.4, 4.0)))
	solids.append(AABB(at + Vector3(-3.8, 9.4, -3.8), Vector3(7.6, 3.7, 7.6)))


## The lamps' faces (the town shader's slot 14 - lit by night - its flame unmoved: no rise).
class _Lamps:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
		var base := verts.size()
		verts.append_array([a, b, c, d])
		for k in 4:
			norms.append(n)
		if (b - a).cross(c - a).dot(n) > 0.0:   # (Godot's front faces wind clockwise)
			idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
		else:
			idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])

	func strip(mid: Vector3, size: Vector2) -> void:
		var hx := size.x * 0.5
		var hz := size.y * 0.5
		quad(mid + Vector3(-hx, 0, -hz), mid + Vector3(hx, 0, -hz), mid + Vector3(hx, 0, hz), mid + Vector3(-hx, 0, hz), Vector3.UP)

	func box(mid: Vector3, size: Vector3) -> void:
		var h := size * 0.5
		var p := [mid + Vector3(-h.x, -h.y, -h.z), mid + Vector3(h.x, -h.y, -h.z), mid + Vector3(h.x, -h.y, h.z), mid + Vector3(-h.x, -h.y, h.z),
			mid + Vector3(-h.x, h.y, -h.z), mid + Vector3(h.x, h.y, -h.z), mid + Vector3(h.x, h.y, h.z), mid + Vector3(-h.x, h.y, h.z)]
		quad(p[4], p[5], p[6], p[7], Vector3.UP)
		quad(p[0], p[1], p[5], p[4], Vector3.FORWARD)
		quad(p[2], p[3], p[7], p[6], Vector3.BACK)
		quad(p[1], p[2], p[6], p[5], Vector3.RIGHT)
		quad(p[3], p[0], p[4], p[7], Vector3.LEFT)

	func mesh() -> ArrayMesh:
		var mm := ArrayMesh.new()
		mm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
		return mm

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = norms
		var cols := PackedColorArray()
		cols.resize(verts.size())
		cols.fill(Color(14.0 / 255.0, 0.0, 0.0))   # (slot 14, its rise 0: lit by night where it stands)
		arr[Mesh.ARRAY_COLOR] = cols
		arr[Mesh.ARRAY_INDEX] = idx
		return arr
