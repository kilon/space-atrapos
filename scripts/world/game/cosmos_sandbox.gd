class_name CosmosSandbox
extends Node
## The sandbox's ways to make a living (a child of Cosmos): every city's people
## by its landing field - the ore buyer (your pack's raw minerals for drachmas),
## the courier's office (a package to carry to a town on another world or a
## station: in your hands - set down, picked up - handed over there for its pay),
## the local pilot (a ride for a fee: their ship comes down on the field, he
## walks over and up its ramp to its pilot's seat, you walk up after him, he
## flies you to a town on another world or a station); your
## scanner (Z: the deposits round you and the places - towns, caves, dungeons,
## pirate camps, lairs, armed foes - marked for a while); raiders' bounties as
## vouchers, handed in at a station's harbour office. Their state rides in the
## save (CosmosGame.extra: "package", "bounties").

const ROLES := {"vendor": "ore buyer", "courier": "courier's office", "pilot": "local pilot"}
const SCAN_TIME := 60.0          # s the scan's marks stay
const SCAN_ORE := 600.0          # m: deposits found within this
const SCAN_FAR := 14000.0        # m: places found within this
const VENDOR_PAY := 1.5          # of a mineral's value (raw ore's worth more to a town than in a station's market)

var cosmos: Cosmos
var scan_marks: Array = []       # [world position (planet-local if planet), planet or null, label, kind, until]
var scan_pulse := 0.0            # (the pulse's ring on the HUD: 1 -> 0)
var _box: Node3D                 # the package set down
var _box_deck: Node3D            # (on a deck: the port, a ship's insides) or null (the ground)
var _box_pl: CosmosPlanet
var _box_at := Vector3.ZERO      # deck-local or planet-local
var _ride: CosmosNpcShip         # the ride you hired, on its way or waiting


func _process(delta: float) -> void:
	scan_pulse = maxf(0.0, scan_pulse - delta)
	var now := Time.get_ticks_msec() / 1000.0
	if not scan_marks.is_empty() and float(scan_marks[0][4]) < now:
		scan_marks = scan_marks.filter(func(m): return float(m[4]) >= now)
	if _box:   # (moved with its world or deck)
		if _box_deck and is_instance_valid(_box_deck):
			_box.global_transform = _box_deck.global_transform * Transform3D(Basis(), _box_at)
		elif _box_pl and is_instance_valid(_box_pl):
			var u := _box_at.normalized()   # (planet-local: it turns with its world)
			_box.global_transform = _box_pl.global_transform * Transform3D(Basis.looking_at(u.cross(Vector3.RIGHT if absf(u.x) < 0.9 else Vector3.FORWARD), u), _box_at)
		else:
			_box.queue_free()
			_box = null
			holding(true)   # (its world gone: it's in your hands again)


# --- Who's who by the field ------------------------------------------------------------

## A city's people beside its landing field: [role, town-local spot] - where Kilon once stood.
static func spots() -> Array:
	return [["vendor", Vector3(-30.0, 0.0, -7.0)], ["courier", Vector3(-30.0, 0.0, 7.0)], ["pilot", Vector3(-12.0, 0.0, 22.0)]]


func prompt_for(x: Node) -> Array:
	if x.role == "captain":   # (a landing pad's ship's pilot, ashore: CosmosLandingField)
		return ["Talk to %s" % str(x.label), "svc:%d" % x.get_instance_id()]
	return ["Talk to the %s" % ROLES[x.role], "svc:%d" % x.get_instance_id()]


func talk(x: Node) -> void:
	match str(x.role):
		"vendor": _vendor(x)
		"courier": _courier(x)
		"pilot": _pilot(x)
		"captain": _captain(x)


func _who(x: Node) -> String:
	return "The %s" % ROLES.get(x.role, "townsman")


func _bye(x: Node) -> Array:
	return ["Farewell", func(): cosmos.converse([[_who(x), "Good roads to you."]], [])]


# --- The ore buyer ------------------------------------------------------------------------

func _ore_in_pack() -> Dictionary:
	var out := {}
	for id in Mining.MINERALS:
		var n: int = CosmosGame.data.count(id)
		if n > 0:
			out[id] = n
	return out


static func ore_price(id: String) -> int:
	return maxi(1, roundi(float(Items.info(id).get("value", 10)) * VENDOR_PAY))


func _vendor(x: Node) -> void:
	var ore := _ore_in_pack()
	var total := 0
	var units := 0
	for id in ore:
		total += ore_price(id) * int(ore[id])
		units += int(ore[id])
	var choices: Array = []
	if units > 0:
		choices.append(["Sell all my ore (%d units: %d dr)" % [units, total], func():
			for id in ore:
				CosmosGame.data.remove_item(id, int(ore[id]))
			CosmosGame.data.add_credits(total)
			cosmos.note_event("ore_sold")
			cosmos.converse([[_who(x), "%d drachmas - counted out. Bring me more." % total]], [_bye(x)])])
	choices.append(["What do you buy?", func():
		var list: Array = []
		for id in Mining.MINERALS:
			list.append("%s %d" % [Items.info(id).get("name", id), ore_price(id)])
		cosmos.converse([[_who(x), "Raw ore, dug or cut from the ground - your mining beam on a deposit (your scanner finds them). Per unit: " + ", ".join(list.slice(0, 8)) + "."]], [_bye(x)])])
	choices.append(_bye(x))
	cosmos.converse([[_who(x), "Ore buyer. I pay fair for what you dig." if units == 0 else "Let's see what you've brought - %d units." % units]], choices)


# --- The courier's office: packages ------------------------------------------------------

func package() -> Dictionary:
	return CosmosGame.extra.get("package", {})


## Your package in your hands (`on`): the walker carrying it.
func holding(on: bool) -> void:
	var w := cosmos.walker
	if w:
		w.set_carry(on and not package().is_empty())


## Delivery jobs from town `t`: towns on the system's other worlds and its stations, a few, each its pay.
func jobs_from(t: Node) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(t.site.get("name", "")) + str(int(Galaxy.time / 300.0)))   # (new ones every five minutes)
	var all: Array = []
	for pl: CosmosPlanet in cosmos.planets:
		if pl == t.planet:
			continue
		for s in pl.towns:
			all.append({"kind": "town", "planet": str(pl.rec.get("name", "")), "town": str(s["name"]), "label": "%s on %s" % [s["name"], pl.rec.get("name", "")],
				"far": pl.global_position.distance_to(t.global_position)})
	for st: CosmosStation in cosmos.stations:
		all.append({"kind": "station", "id": str(st.record.get("id", "")), "label": cosmos.label_of(st), "far": st.global_position.distance_to(t.global_position)})
	var out: Array = []
	for i in mini(3, all.size()):
		var j := rng.randi_range(0, all.size() - 1)
		var d: Dictionary = all[j]
		all.remove_at(j)
		d["reward"] = 280 + roundi(clampf(float(d["far"]) / 1000.0, 0.0, 120.0)) + rng.randi_range(0, 60) + (40 if d["kind"] == "station" else 0)   # (~30 of them and the tutorial's rewards: a first ship, ~13,800 dr)
		d["from"] = str(t.site.get("name", ""))
		out.append(d)
	return out


func _courier(x: Node) -> void:
	var p := package()
	var here := str(x.town.site.get("name", ""))
	var here_pl := str(x.town.planet.rec.get("name", ""))
	var choices: Array = []
	if not p.is_empty():
		var dest: Dictionary = p["dest"]
		if dest["kind"] == "town" and dest["town"] == here and dest["planet"] == here_pl:
			if cosmos.walker and cosmos.walker.carrying:
				choices.append(["Hand over the package (%d dr)" % int(p["reward"]), func(): _deliver(x, p)])
			else:
				cosmos.converse([[_who(x), "That's our package? Bring it here - I'll not fetch it off the ground."]], [_bye(x)])
				return
		else:
			choices.append(["Give the package back (no pay)", func():
				CosmosGame.extra.erase("package")
				holding(false)
				_clear_box()
				cosmos.converse([[_who(x), "Back on the shelf it goes."]], [_bye(x)])])
		choices.append(_bye(x))
		cosmos.converse([[_who(x), "Yours is for %s. The local pilot by the field flies there - for a fee." % dest["label"]]], choices)
		return
	for j in jobs_from(x.town):
		var job: Dictionary = j
		choices.append(["A package for %s - %d dr" % [job["label"], int(job["reward"])], func(): _accept(x, job)])
	choices.append(_bye(x))
	cosmos.converse([[_who(x), "Couriers wanted - packages for the other worlds and the stations. You carry it, the pay's on delivery."]], choices)


func _accept(x: Node, job: Dictionary) -> void:
	CosmosGame.extra["package"] = {"dest": job, "reward": int(job["reward"]), "from": job["from"]}
	if cosmos.walker:
		cosmos.walker.hands("pick_up", func(): holding(true))
	cosmos.note_event("package_taken")
	cosmos.converse([[_who(x), "Here - mind it. For %s; the local pilot can fly you there. Set it down when you must (%s), but don't leave it." % [job["label"], Keybinds.keys_text("drop")]]], [])


func _deliver(x: Node, p: Dictionary) -> void:
	CosmosGame.extra.erase("package")
	if cosmos.walker:
		cosmos.walker.hands("put_down", func(): holding(false))
	CosmosGame.data.add_credits(int(p["reward"]))
	CosmosGame.extra["deliveries"] = int(CosmosGame.extra.get("deliveries", 0)) + 1
	cosmos.note_event("package_delivered")
	cosmos.converse([[_who(x) if x else "The harbour officer", "Signed for - %d drachmas. Come back for more." % int(p["reward"])]], [])


## At a station's port: the harbour officer takes a package for this station, and bounty vouchers.
func port_choices(role: String, who: String) -> Array:
	var out: Array = []
	if role != "officer":
		return out
	var p := package()
	var st := cosmos.port_station()
	if not p.is_empty() and st and p["dest"]["kind"] == "station" and str(p["dest"]["id"]) == str(st.record.get("id", "")):
		if cosmos.walker and cosmos.walker.carrying:
			out.append(["Hand over the package (%d dr)" % int(p["reward"]), func(): _deliver(null, p)])
	var b := bounties()
	if int(b.get("dr", 0)) > 0:
		out.append(["Hand in my bounty vouchers (%d: %d dr)" % [int(b["n"]), int(b["dr"])], func():
			CosmosGame.data.add_credits(int(b["dr"]))
			CosmosGame.extra.erase("bounties")
			cosmos.note_event("bounty_claimed")
			cosmos.converse([[who, "%d drachmas from the empire's treasury - for the raiders. Good hunting." % int(b["dr"])]], [])])
	return out


# --- A package set down, picked up -----------------------------------------------------

## H: the package out of your hands onto the ground (or the deck), or back into them.
func drop_or_pick() -> void:
	var w := cosmos.walker
	if w == null or w.busy() or package().is_empty():
		return
	if w.carrying:
		w.hands("put_down", func(): _set_down(w))
	elif _box and _box.global_position.distance_to(w.global_position) < 2.2:
		w.hands("pick_up", func():
			_clear_box()
			holding(true)
			cosmos.note_event("box_up"))


func box_near() -> bool:
	var w := cosmos.walker
	return w != null and _box != null and not w.carrying and _box.global_position.distance_to(w.global_position) < 2.2


func _set_down(w: CosmosWalker) -> void:
	w.set_carry(false)
	cosmos.note_event("box_down")
	_clear_box()
	var c := MeshInstance3D.new()
	c.mesh = EmpireKit.crate_mesh(true)
	c.material_override = EmpireKit.mat("inside", "minoa")
	c.scale = Vector3(0.33, 0.36, 0.25)
	cosmos.world.add_child(c)
	_box = c
	var at := w.global_position + w.facing * 0.42
	if w.deck:
		_box_deck = w.deck
		var l: Vector3 = w.deck.to_local(at)
		l.y = float(w.deck.floor_y(l)) if w.deck.has_method("floor_y") else 0.0
		_box_at = l
	else:
		_box_pl = w.planet
		var local: Vector3 = w.planet.to_local(at)
		_box_at = local.normalized() * (w.planet.radius + w.floor_at(local))


func _clear_box() -> void:
	if _box:
		_box.queue_free()
	_box = null
	_box_deck = null
	_box_pl = null


# --- The local pilot: rides ----------------------------------------------------------------

## A town's landing field on `pl` (planet-local): level, x along it, on its deck.
static func field_of(pl: CosmosPlanet, site: Dictionary) -> Transform3D:
	var xf := CosmosTown.frame(site, pl.radius)
	var half := 85.0 if str(site.get("kind", "")) == "city" else 45.0
	return Transform3D(xf.basis, xf * Vector3(half + 38.0, 0.05, 0.0))


## A hired ride still waiting on town `t`'s field (its pilot gone aboard or on his way): no new pilot there yet.
func pilot_busy(t: Node) -> bool:
	return _ride != null and is_instance_valid(_ride) and _ride.hire.get("town") == t and _ride.hire_state() in ["arrive", "wait"]


func _fee(far: float) -> int:
	return clampi(25 + roundi(far / 2500.0), 25, 140)


func _pilot(x: Node) -> void:
	if _ride and is_instance_valid(_ride) and _ride.hire.get("pilot") == x:
		cosmos.converse([[_who(x), "My ship's coming down on the field for you - I'll be aboard; up the ramp when you're ready."]], [_bye(x)])
		return
	var choices: Array = []
	for o in ride_offers(x.town):
		var d: Dictionary = o[2]
		var fee: int = o[1]
		choices.append(["Fly me to %s - %d dr" % [o[0], fee], func(): _hire(x, d, fee)])
	choices.append(_bye(x))
	cosmos.converse([[_who(x), "Need a ride off-world? I fly to the other worlds' towns, the stations - and through the gates. Pay up front."]], choices)


## Where a pilot of town `t` flies you, and for how much: [[label, fee, destination]] -
## your package's place first, a city on each other world, the system's stations,
## the systems through its gates and one gate on (RIDE_JUMPS).
const RIDE_JUMPS := 2
const JUMP_FEE := 150            # dr a jump (and a run to the gate: JUMP_BASE)
const JUMP_BASE := 60


func ride_offers(t: Node) -> Array:
	var dests: Array = []
	var p := package()
	if not p.is_empty() and str(p["dest"].get("kind", "")) in ["town", "station"]:
		dests.append(p["dest"])
	for pl: CosmosPlanet in cosmos.planets:
		if pl == t.planet or pl.towns.is_empty():
			continue
		for s in pl.towns:
			if str(s.get("kind", "")) == "city":
				dests.append({"kind": "town", "planet": str(pl.rec.get("name", "")), "town": str(s["name"]), "label": "%s on %s" % [s["name"], pl.rec.get("name", "")]})
				break
	for st: CosmosStation in cosmos.stations:
		dests.append({"kind": "station", "id": str(st.record.get("id", "")), "label": cosmos.label_of(st)})
	var seen := {}
	var out: Array = []
	for d in dests:
		var key := str(d["label"])
		if seen.has(key) or out.size() >= 6:
			continue
		seen[key] = true
		var node := _dest_node(d)
		if node == null:
			continue
		out.append([str(d["label"]), _fee(node.global_position.distance_to(t.global_position)), d])
	for d in systems_near():
		out.append([str(d["label"]), int(d["fee"]), d])
	return out


## The systems a ride reaches from here: through this system's gates, and one gate on
## (each with a station to set you down at) - [{kind "system", sys, via (the first gate's), jumps, label, fee}].
func systems_near() -> Array:
	var here := str(cosmos.system_id)
	var out: Array = []
	var seen := {here: true}
	var ring: Array = [[here, ""]]
	for jumps in range(1, RIDE_JUMPS + 1):
		var next: Array = []
		for e in ring:
			var gates: Dictionary = Galaxy.system(str(e[0])).get("gates", {})
			for to in gates:
				var sid := str(to)
				if seen.has(sid) or not Galaxy.systems.has(sid):
					continue
				seen[sid] = true
				var via: String = sid if jumps == 1 else str(e[1])
				next.append([sid, via])
				if jumps == 1 and cosmos._gate_to(sid) == null:
					continue
				if (Galaxy.system(sid).get("stations", []) as Array).is_empty():
					continue   # (nowhere to set you down)
				out.append({"kind": "system", "sys": sid, "via": via, "jumps": jumps, "fee": JUMP_BASE + JUMP_FEE * jumps,
					"label": "the %s system (%d jump%s)" % [Galaxy.system(sid).get("name", sid), jumps, "" if jumps == 1 else "s"]})
		ring = next
	out.sort_custom(func(a, b): return int(a["jumps"]) < int(b["jumps"]))
	return out.slice(0, 4)


func _dest_node(d: Dictionary) -> Node3D:
	if d["kind"] == "station":
		return cosmos._station_by_id(str(d["id"]))
	if d["kind"] == "system":
		return cosmos._gate_to(str(d["via"]))
	for pl: CosmosPlanet in cosmos.planets:
		if str(pl.rec.get("name", "")) == str(d["planet"]):
			return pl
	return null


## Where a hired ride flies (CosmosNpcShip.hire_ride's `to`) for destination `d`: {} if it's not there.
func ride_to(d: Dictionary) -> Dictionary:
	if d["kind"] == "station":
		var st := _dest_node(d)
		return {"station": st} if st else {}
	if d["kind"] == "system":
		var g := _dest_node(d)
		return {"gate": g, "sys": str(d["sys"])} if g else {}
	var dpl: CosmosPlanet = _dest_node(d)
	if dpl:
		for s in dpl.towns:
			if str(s["name"]) == str(d["town"]):
				return {"pl": dpl, "field": field_of(dpl, s)}
	return {}


func _hire(x: Node, d: Dictionary, fee: int) -> void:
	if not CosmosGame.data.spend(fee):
		cosmos.converse([[_who(x), "That's %d drachmas - come back when you have it." % fee]], [])
		return
	var t: Node = x.town
	var to := ride_to(d)
	if to.is_empty():
		CosmosGame.data.add_credits(fee)
		return
	var s := CosmosNpcShip.new()
	s.setup("trader", cosmos, randi(), str(t.site.get("empire", "minoa")), "trader")   # (a small trader: its pilot's walk to its bridge a short one)
	s.label = "The local pilot's ship"
	cosmos.world.add_child(s)
	cosmos.npc_ships.append(s)
	s.hire_ride(t.planet, field_of(t.planet, t.site), to)
	s.hire["pilot"] = x   # (he walks over to it once it's down, up its ramp, to its pilot's seat - and flies you)
	s.hire["town"] = t
	_ride = s
	cosmos.note_event("ride_hired")
	cosmos.converse([[_who(x), "Done. My ship's coming down on the field - walk up the ramp when it's down; I'll take you to %s." % d["label"]]], [])


# --- The landing pads' pilots: rides off their pads ----------------------------------------

## A landing pad's ship's pilot ashore (CosmosLandingField): a ride in his own ship -
## off its pad, where you pay to go; a courier's skiff has no room for you.
func _captain(x: Node) -> void:
	var who := str(x.get_meta("who", "The pilot"))
	var bye := ["Farewell", func(): cosmos.converse([[who, "Clear skies."]], [])]
	if x.get_meta("hired", false):
		cosmos.converse([[who, "Up the ramp after me - we're off once you're aboard and I'm at the controls."]], [])
		return
	var lf = CosmosLandingField.of(cosmos)
	if lf.record_of(x).is_empty():
		cosmos.converse([[who, "My ship's due off - another time."]], [bye])
		return
	if x.get_meta("courier", false):
		cosmos.converse([[who, "A courier's skiff, that one - room for me and the post, no more. The shuttles' pilots take passengers."]], [bye])
		return
	var choices: Array = []
	for o in ride_offers(x.town):
		var d: Dictionary = o[2]
		var fee: int = o[1]
		choices.append(["Fly me to %s - %d dr" % [o[0], fee], func(): hire_captain(x, d, fee)])
	choices.append(bye)
	cosmos.converse([[who, "%s - that's my shuttle on pad %d. A ride? This system's stations, the other worlds - and through the gates. Pay up front." % [who, int(x.get_meta("pad", 1))]]], choices)


## Pilot `x` hired: the fee taken, his ship yours to `d` - he walks back to it, you after him.
func hire_captain(x: Node, d: Dictionary, fee: int) -> bool:
	var who := str(x.get_meta("who", "The pilot"))
	var to := ride_to(d)
	if to.is_empty():
		return false
	if not CosmosGame.data.spend(fee):
		cosmos.converse([[who, "That's %d drachmas - come back when you have it." % fee]], [])
		return false
	var s: CosmosNpcShip = CosmosLandingField.of(cosmos).hire(x, to)
	if s == null:
		CosmosGame.data.add_credits(fee)
		return false
	x.set_meta("hired", true)
	cosmos.note_event("ride_hired")
	cosmos.converse([[who, "Done - %s it is. Follow me to my ship; up the ramp after me." % d["label"]]], [])
	return true


# --- The scanner -------------------------------------------------------------------------

## Z on foot: a pulse out from you - the deposits near you, and the places further
## off (towns, caves, dungeons, pirate camps, lairs, armed foes) marked for a minute.
func scan() -> void:
	var w := cosmos.walker
	if w == null or w.deck != null or w.planet == null:
		cosmos.hud.flash("The scanner works out on a world's ground")
		return
	var pl := w.planet
	var me := w.global_position
	var until := Time.get_ticks_msec() / 1000.0 + SCAN_TIME
	scan_marks = []
	scan_pulse = 1.0
	var n_ore := 0
	if cosmos.deposits and cosmos.deposits.planet == pl:
		for k in cosmos.deposits.deps:
			var dep: Dictionary = cosmos.deposits.deps[k]
			var at: Vector3 = pl.to_global(dep["at"] as Vector3)
			if at.distance_to(me) < SCAN_ORE:
				scan_marks.append([dep["at"], pl, "%s (%d)" % [Items.info(str(dep["mineral"])).get("name", dep["mineral"]), int(dep["units"])], "ore", until])
				n_ore += 1
	var n_veins := 0
	if cosmos.veins:   # (the veins under the ground near you: their ghosts through it, and marks)
		for m in cosmos.veins.reveal(me):
			scan_marks.append([m[0], pl, m[1], "ore", until])
			n_veins += 1
	var places: Array = []
	for s in pl.towns:
		places.append([(s["dir"] as Vector3) * (pl.radius + float(s["h"])), "%s (%s)" % [s["name"], s["kind"]], "town"])
	for e in cosmos.dungeons_of(pl):
		var site: Dictionary = e[0]
		places.append([(site["dir"] as Vector3) * (pl.radius + pl.shape.height(site["dir"])), "%s (%s)" % [site.get("name", "?"), site.get("kind", "cave")], "cave"])
	for camp in cosmos.camps_of(pl):
		places.append([camp[0], "Pirate camp", "foe"])
	for lr in cosmos.lairs:
		if is_instance_valid(lr) and lr.global_position.distance_to(me) < SCAN_FAR:
			places.append([pl.to_local(lr.global_position), "Bio-signature", "foe"])
	for c in cosmos.creatures:
		if is_instance_valid(c) and c.get("hostile") and c.global_position.distance_to(me) < 400.0:
			places.append([pl.to_local(c.global_position), str(c.get("label")) if c.get("label") else "Creature", "foe"])
	var found := {"town": 0, "cave": 0, "foe": 0}
	for p in places:
		var at: Vector3 = pl.to_global(p[0] as Vector3)
		if at.distance_to(me) < SCAN_FAR:
			scan_marks.append([p[0], pl, p[1], p[2], until])
			found[p[2]] = int(found[p[2]]) + 1
	var n_pads := 0
	var lf = CosmosLandingField.of(cosmos)
	for s in pl.towns:   # (the towns' landing pads near you: free, or a ship on it)
		var xf := CosmosTown.frame(s, pl.radius)
		if (pl.to_global(xf.origin) as Vector3).distance_to(me) > 4000.0:
			continue
		for pd in CosmosLandingField.pads_of(s):
			var key := CosmosLandingField.key_of(pl, s, pd)
			var sl := CosmosLandingField.slot_at(key, pd, Galaxy.time, str(s.get("empire", "")))
			var used: bool = lf.live.has(key) or (sl["busy"] and Galaxy.time >= float(sl["arrive"]) and Galaxy.time < float(sl["gone"]))
			scan_marks.append([xf * (pd["at"] as Vector3), pl, "Pad %d, %s (%s)" % [int(pd["id"]), s["name"], "a ship on it" if used else "free"], "town", until])
			n_pads += 1
	cosmos.note_event("scanned")
	cosmos.hud.flash("Scan: %d deposits near, %d veins underground, %d towns, %d landing pads, %d caves and dungeons, %d foes or camps" % [n_ore, n_veins, found["town"], n_pads, found["cave"], found["foe"]], 4.0)


# --- Bounties ----------------------------------------------------------------------------

func bounties() -> Dictionary:
	return CosmosGame.extra.get("bounties", {})


func add_bounty(dr: int) -> void:
	var b := bounties()
	b["n"] = int(b.get("n", 0)) + 1
	b["dr"] = int(b.get("dr", 0)) + dr
	CosmosGame.extra["bounties"] = b
