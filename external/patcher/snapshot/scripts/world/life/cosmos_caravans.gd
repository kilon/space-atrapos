class_name CosmosCaravans
extends Node
## The life of a world's roads (CosmosRoads) in the 3D game: its logistics and
## its travellers.
##   Logistics - each town makes a few goods (a village its farms' and herds':
##     grain, oil, wine, cheese, wool...; a city its workshops': pottery, tools,
##     cloth, bronze...) and uses up what it doesn't make: a stock per town
##     (stock_of). Caravans load what their town has most of and the town they
##     make for has least, carry it there along the roads and unload it.
##   Travellers - caravans (traders, their guards, pack donkeys), couriers
##     running between towns, pilgrims bound for a city's shrine, patrols of
##     armed guards. Far from you each is only a place along its road over time
##     (a few numbers, SIM_HZ times a second); within NEAR they're there -
##     CosmosTraveller and the donkeys (CosmosCreature, driven along) walking
##     in a column - and gone back into numbers past GONE.
##   Hostiles - raiders out of the pirates' camps fall on travellers passing
##     near (a raid you see: CosmosTraveller raiders run in; one out of your
##     sight: the odds of its guards against them - robbed, its remains left
##     in the road: CosmosLoot.drop_wreck), and hunting beasts go for them
##     (driven at them here; their bites dealt here). The guards fight, the
##     rest run; the dead drop their loot (CosmosLoot). The event log notes
##     what you witness. Shoot at a caravan and its guards turn on you.
## Nothing of it is saved: each world's starts afresh, from its seed, each session.
##   CosmosCaravans.attach(cosmos)   # (and its roads and loot)

const NEAR := 320.0             # m: a group's people out within this of you
const GONE := 360.0             # ...and back to numbers past this (Cosmos frees npcs past 390)
const SIM_HZ := 2.0
const COLUMN := 3.4             # m between people in a column
const CAMP_NEAR := 900.0        # m: a pirate camp this near: its raiders after travellers
const CAMP_RAID := 0.12         # raids a minute on a group near a camp, out of your sight
const WILD_RAID := 0.004        # ...and anywhere else
const SEEN_RAID := 0.5          # the chance a group you come near is ambushed while you watch (near a camp; a quarter of it elsewhere)
const PER_KM := 0.7             # groups on the roads a km of road
const CARAVAN_CLASS := "res://scripts/world/life/cosmos_caravans.gd"

const MAKES := {
	"village": ["grain", "olive_oil", "wine", "cheese", "honey", "figs", "wool", "timber", "lentils", "dried_fish"],
	"city": ["pottery", "tools", "clothing", "bronze_ingots", "glassware", "linen", "furniture", "perfume", "jewellery"],
}
const KINDS := [["caravan", 0.5], ["patrol", 0.17], ["courier", 0.15], ["pilgrims", 0.18]]

static var _worlds := {}        # planet key (CosmosRoads._pid) -> its roads' life

var cosmos: Node
var _sim_t := 0.0
var _queue: Array = []          # [group, member index or -1 (a raider), planet] - put in one a frame
var _bites := {}                # creature instance id -> s till it bites again
var _rng := RandomNumberGenerator.new()


## The Cosmos's caravans (and its roads and loot): made as its children the first time.
static func attach(c: Node) -> CosmosCaravans:
	CosmosRoads.of(c)
	CosmosLoot.of(c)
	var n := c.get_node_or_null("Caravans") as CosmosCaravans
	if n == null:
		n = load(CARAVAN_CLASS).new()
		n.name = "Caravans"
		n.cosmos = c
		c.add_child(n)
	return n


## A world's roads' life ({} until its roads are made).
static func world_of(pl: CosmosPlanet) -> Dictionary:
	return _worlds.get(CosmosRoads._pid(pl), {}) if pl else {}


## What town `i` of `pl` has in store: good -> how much.
static func stock_of(pl: CosmosPlanet, i: int) -> Dictionary:
	var w := world_of(pl)
	return w["stock"][i] if not w.is_empty() and i < (w["stock"] as Array).size() else {}


func _ready() -> void:
	process_priority = -10   # (before the creatures: the donkeys and the beasts driven, then they move)
	_rng.randomize()


func _process(delta: float) -> void:
	if cosmos == null or not cosmos.get("built"):
		return
	delta = minf(delta, 0.1)
	var roads := CosmosRoads.of(cosmos)
	var f: Node3D = cosmos.focus()
	if f == null:
		return
	var life: CosmosPlanet = cosmos.life_planet()
	if cosmos.get("dungeon") != null:
		life = null   # (under the ground: the roads' people wait)
	_sim_t += delta
	var sim := _sim_t >= 1.0 / SIM_HZ
	var dt := _sim_t
	if sim:
		_sim_t = 0.0
	for pl: CosmosPlanet in cosmos.planets:
		var rl: Array = roads.roads_of(pl)
		if rl.is_empty():
			continue
		var w := _world(pl, rl)
		if sim:
			_simulate(w, pl, rl, dt)
		if pl == life:
			_near(w, pl, rl, f.global_position - pl.global_position)
			_live(w, pl, rl, delta)
		else:
			for g in w["groups"]:
				if g["out"]:
					_put_away(g)
	if not _queue.is_empty():
		_put_in(_queue.pop_front())


# --- The worlds' logistics, simulated -------------------------------------------------------

func _world(pl: CosmosPlanet, rl: Array) -> Dictionary:
	var key := CosmosRoads._pid(pl)
	if _worlds.has(key):
		return _worlds[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pl.rec.get("seed", 1)) * 71 + 3
	var w := {"groups": [], "stock": [], "makes": [], "next": 0, "rng": rng, "add_t": 60.0}
	for s in pl.towns:
		var pool: Array = (MAKES[str(s["kind"])] as Array).duplicate()
		var makes: Array = []
		for k in 3:
			makes.append(pool.pop_at(rng.randi() % pool.size()))
		w["makes"].append(makes)
		var st := {}
		for g in makes:
			st[g] = float(rng.randi_range(14, 40))
		w["stock"].append(st)
	var total := 0.0
	for r in rl:
		total += float(r["length"])
	w["want"] = clampi(roundi(total / 1000.0 * PER_KM), rl.size(), 18)
	for i in int(w["want"]):
		var k := rng.randi() % rl.size()
		_new_group(w, pl, rl, k, 1 if rng.randf() < 0.5 else -1, rng.randf() * float(rl[k]["length"]))
	_worlds[key] = w
	return w


## A group on road k heading `dir` (+1 to its b end, -1 to its a end), `s` m along it.
func _new_group(w: Dictionary, pl: CosmosPlanet, rl: Array, k: int, dir: int, s: float, kind := "") -> Dictionary:
	var rng: RandomNumberGenerator = w["rng"]
	if kind == "":
		var x := rng.randf()
		for kk in KINDS:
			x -= float(kk[1])
			if x <= 0.0:
				kind = kk[0]
				break
		if kind == "":
			kind = "caravan"
	var members: Array = []
	var speed := 1.35
	match kind:
		"caravan":
			for i in rng.randi_range(1, 2):
				members.append({"role": "guard"})
			for i in rng.randi_range(1, 2):
				members.append({"role": "trader"})
			for i in rng.randi_range(1, 2):
				members.append({"role": "donkey"})
			if rng.randf() < 0.5:
				members.append({"role": "guard"})   # (one at the back)
		"patrol":
			for i in rng.randi_range(2, 3):
				members.append({"role": "guard"})
			speed = 1.6
		"courier":
			members.append({"role": "courier"})
			speed = 3.6
		"pilgrims":
			for i in rng.randi_range(2, 4):
				members.append({"role": "pilgrim"})
			speed = 1.1
	for m in members:
		m["seed"] = rng.randi()
		m["hp"] = -1.0
		m["goods"] = {}
		m["dead"] = false
	var g := {"id": int(w["next"]), "kind": kind, "road": k, "dir": dir, "s": s, "speed": speed, "members": members,
		"halt": 0.0, "out": false, "nodes": [], "angry": false, "ambush": -1.0, "raiders": [], "raid": false, "seen": {},
		"empire": str(pl.towns[0].get("empire", ""))}
	w["next"] = int(w["next"]) + 1
	_titled(g, pl, rl)
	if kind == "caravan":
		_load(w, g, _from(g, rl), _dest(g, rl))
	elif kind == "courier":
		g["members"][0]["goods"] = {"papyrus": rng.randi_range(1, 3)}
	elif kind == "pilgrims":
		for m in members:
			m["goods"] = {"incense": 1}
	w["groups"].append(g)
	return g


static func _dest(g: Dictionary, rl: Array) -> int:
	return int(rl[g["road"]]["b"] if int(g["dir"]) > 0 else rl[g["road"]]["a"])


static func _from(g: Dictionary, rl: Array) -> int:
	return int(rl[g["road"]]["a"] if int(g["dir"]) > 0 else rl[g["road"]]["b"])


func _titled(g: Dictionary, pl: CosmosPlanet, rl: Array) -> void:
	var to := str(pl.towns[_dest(g, rl)]["name"])
	g["title"] = {"caravan": "caravan to %s", "patrol": "patrol on the road to %s", "courier": "courier bound for %s",
		"pilgrims": "pilgrims on the way to %s"}[g["kind"]] % to


## A caravan loaded at town `from`: what it has most of that town `to` has least of.
func _load(w: Dictionary, g: Dictionary, from: int, to: int) -> void:
	var here: Dictionary = w["stock"][from]
	var there: Dictionary = w["stock"][to]
	var goods: Array = (w["makes"][from] as Array).duplicate()
	goods.sort_custom(func(a, b): return float(here.get(a, 0.0)) - float(there.get(a, 0.0)) > float(here.get(b, 0.0)) - float(there.get(b, 0.0)))
	var carriers: Array = (g["members"] as Array).filter(func(m): return m["role"] in ["donkey", "trader"] and not m["dead"])
	if carriers.is_empty():
		return
	var ci := 0
	for good in goods.slice(0, 2):
		var have := float(here.get(good, 0.0))
		var n := mini(int(have - 4.0), 12)
		if n <= 0:
			continue
		here[good] = have - n
		while n > 0:   # (shared out: the donkeys the most)
			var m: Dictionary = carriers[ci % carriers.size()]
			var k := mini(n, 6 if m["role"] == "donkey" else 3)
			m["goods"][good] = int(m["goods"].get(good, 0)) + k
			n -= k
			ci += 1


## Arrived: its load into the town's stock, then off along another of its roads.
func _arrive(w: Dictionary, g: Dictionary, pl: CosmosPlanet, rl: Array) -> void:
	var town := _dest(g, rl)
	var st: Dictionary = w["stock"][town]
	for m in g["members"]:
		if m["role"] in ["donkey", "trader"]:
			for good in m["goods"]:
				st[good] = float(st.get(good, 0.0)) + float(m["goods"][good])
			(m["goods"] as Dictionary).clear()
	var rng: RandomNumberGenerator = w["rng"]
	var best := -1
	var bs := -INF
	for k in rl.size():
		if int(rl[k]["a"]) != town and int(rl[k]["b"]) != town:
			continue
		var other := int(rl[k]["b"]) if int(rl[k]["a"]) == town else int(rl[k]["a"])
		var score := rng.randf() * 6.0
		if g["kind"] == "caravan":   # (where its goods are wanted most)
			for good in w["makes"][town]:
				score += float(st.get(good, 0.0)) - float((w["stock"][other] as Dictionary).get(good, 0.0))
		elif g["kind"] == "pilgrims" and str(pl.towns[other]["kind"]) == "city":
			score += 20.0
		if k == int(g["road"]) and rl.size() > 1:
			score -= 8.0   # (not straight back the way it came, if there's another way)
		if score > bs:
			bs = score
			best = k
	if best < 0:
		g["gone"] = true
		return
	g["road"] = best
	g["dir"] = 1 if int(rl[best]["a"]) == town else -1
	g["s"] = 0.0 if int(g["dir"]) > 0 else float(rl[best]["length"])
	g["halt"] = rng.randf_range(20.0, 60.0)
	_titled(g, pl, rl)
	if g["kind"] == "caravan":
		_load(w, g, town, _dest(g, rl))


func _simulate(w: Dictionary, pl: CosmosPlanet, rl: Array, dt: float) -> void:
	var rng: RandomNumberGenerator = w["rng"]
	# (the towns' making and using: a unit a minute of each good it makes, a third of one of the rest)
	for i in (w["stock"] as Array).size():
		var st: Dictionary = w["stock"][i]
		for good in w["makes"][i]:
			st[good] = minf(float(st.get(good, 0.0)) + dt / 60.0, 80.0)
		for good in st:
			if not good in w["makes"][i]:
				st[good] = maxf(float(st[good]) - dt / 180.0, 0.0)
	var camps: Array = cosmos.camps_of(pl) if cosmos.has_method("camps_of") else []
	for g in w["groups"]:
		if g["out"]:
			continue
		if float(g["halt"]) > 0.0:
			g["halt"] = float(g["halt"]) - dt
			continue
		var L := float(rl[g["road"]]["length"])
		g["s"] = float(g["s"]) + int(g["dir"]) * float(g["speed"]) * dt
		if (int(g["dir"]) > 0 and float(g["s"]) >= L) or (int(g["dir"]) < 0 and float(g["s"]) <= 0.0):
			g["s"] = clampf(float(g["s"]), 0.0, L)
			_arrive(w, g, pl, rl)
			continue
		# Out of your sight, raiders and their odds.
		var at := where(pl, rl, g, float(g["s"]))
		var p := WILD_RAID
		for c in camps:
			if (c[0] as Vector3).distance_to(at) < CAMP_NEAR:
				p = CAMP_RAID
				break
		if rng.randf() < p * dt / 60.0:
			_far_raid(g, pl, at, rng)
	for g in w["groups"]:
		if g.get("gone", false) and g["out"]:
			_put_away(g)
	w["groups"] = (w["groups"] as Array).filter(func(g): return not g.get("gone", false))
	# New travellers out of the towns, while the roads have fewer than they should.
	w["add_t"] = float(w["add_t"]) - dt
	if float(w["add_t"]) <= 0.0:
		w["add_t"] = rng.randf_range(90.0, 240.0)
		if (w["groups"] as Array).size() < int(w["want"]):
			var k := rng.randi() % rl.size()
			var dir := 1 if rng.randf() < 0.5 else -1
			var g := _new_group(w, pl, rl, k, dir, 0.0 if dir > 0 else float(rl[k]["length"]))
			g["halt"] = rng.randf_range(5.0, 30.0)


## A raid out of your sight: its guards against the raiders - driven off (and
## maybe one of them lost), or robbed to the last, its remains in the road.
func _far_raid(g: Dictionary, pl: CosmosPlanet, at: Vector3, rng: RandomNumberGenerator) -> void:
	var guards := (g["members"] as Array).filter(func(m): return m["role"] == "guard" and not m["dead"]).size()
	var win := clampf(0.2 + 0.22 * guards, 0.1, 0.9)
	if rng.randf() < win:
		if rng.randf() < 0.3:
			var alive: Array = (g["members"] as Array).filter(func(m): return not m["dead"])
			if alive.size() > 1:
				alive[rng.randi() % alive.size()]["dead"] = true
		g["members"] = (g["members"] as Array).filter(func(m): return not m["dead"])
		return
	var loot := {"credits": rng.randi_range(10, 60)}
	for m in g["members"]:
		for good in m["goods"]:
			loot[good] = int(loot.get(good, 0)) + int(m["goods"][good]) / 2   # (what the raiders left of it)
	for good in loot.keys():
		if int(loot[good]) <= 0:
			loot.erase(good)
	CosmosLoot.of(cosmos).drop_wreck(pl, at, "remains of the %s" % str(g["title"]), loot)
	g["gone"] = true


## Where a group's `s` m along its road is (planet-local), `side` m to its right.
static func where(pl: CosmosPlanet, rl: Array, g: Dictionary, s: float, side := 0.0) -> Vector3:
	var road: Dictionary = rl[g["road"]]
	var d := CosmosRoads.point(road, s)
	if side != 0.0:
		var ahead := CosmosRoads.point(road, s + 1.5 * int(g["dir"]))
		var right := (ahead - d).cross(d)
		if right.length() > 1e-9:
			d = (d * pl.radius + right.normalized() * side).normalized()
	return d * (pl.radius + maxf(pl.shape.height(d), 0.0))


# --- Near you: its people there ------------------------------------------------------------

func _near(w: Dictionary, pl: CosmosPlanet, rl: Array, here: Vector3) -> void:
	for g in w["groups"]:
		var d := where(pl, rl, g, float(g["s"])).distance_to(here)
		if not g["out"] and d < NEAR:
			_put_out(g, pl, rl, here)
		elif g["out"] and d > GONE:
			_put_away(g)


func _put_out(g: Dictionary, pl: CosmosPlanet, rl: Array, _here: Vector3) -> void:
	g["out"] = true
	g["pl"] = pl
	g["nodes"] = []
	(g["nodes"] as Array).resize((g["members"] as Array).size())
	for i in (g["members"] as Array).size():
		if not g["members"][i]["dead"]:
			_queue.append([g, i, pl])
	# (will raiders fall on it while you watch? likelier near a pirates' camp)
	var at := where(pl, rl, g, float(g["s"]))
	var camp := _camp_near(pl, at)
	var p := SEEN_RAID if camp != Vector3.INF else SEEN_RAID * 0.25
	g["ambush"] = _rng.randf_range(12.0, 45.0) if _rng.randf() < p and g["kind"] != "patrol" and not g.get("raided", false) else -1.0


func _camp_near(pl: CosmosPlanet, at: Vector3) -> Vector3:
	if not cosmos.has_method("camps_of"):
		return Vector3.INF
	var best := Vector3.INF
	var bd := CAMP_NEAR
	for c in cosmos.camps_of(pl):
		var d := (c[0] as Vector3).distance_to(at)
		if d < bd:
			bd = d
			best = c[0]
	return best


## Back into numbers: its people's health and loads kept, the dead gone.
func _put_away(g: Dictionary) -> void:
	for i in (g["nodes"] as Array).size():
		var n = g["nodes"][i]
		if n != null and is_instance_valid(n):
			var m: Dictionary = g["members"][i]
			if n.get("dead"):
				m["dead"] = true
			else:
				m["hp"] = float(n.get("hp"))
				n.queue_free()
	for r in g["raiders"]:
		if is_instance_valid(r) and not r.get("dead"):
			r.queue_free()
	g["raiders"] = []
	g["nodes"] = []
	g["out"] = false
	_queue = _queue.filter(func(q): return not is_same(q[0], g))
	g["members"] = (g["members"] as Array).filter(func(m): return not m["dead"])
	if (g["members"] as Array).filter(func(m): return m["role"] != "donkey").is_empty():
		g["gone"] = true


## One of a group's people (or a raider: index -1) put in the world.
func _put_in(q: Array) -> void:
	var g: Dictionary = q[0]
	var i: int = q[1]
	var pl: CosmosPlanet = q[2]
	if not g["out"] or not is_instance_valid(pl):
		return
	var rl: Array = CosmosRoads.of(cosmos).roads_of(pl)
	if rl.is_empty():
		return
	var world: Node3D = cosmos.world
	if i < 0:   # (a raider: out of the camp's side of the road)
		var r := CosmosTraveller.new()
		r.cosmos = cosmos
		r.traveller(pl, "raider", "pirates", _rng.randi())
		world.add_child(r)
		var at: Vector3 = q[3]
		var d := at.normalized()
		r.global_position = pl.global_position + d * (pl.radius + maxf(pl.shape.height(d), 0.0))
		cosmos.npcs.append(r)
		g["raiders"].append(r)
		return
	var m: Dictionary = g["members"][i]
	var slot := _slot(g, i)
	var local := where(pl, rl, g, float(g["s"]) - int(g["dir"]) * COLUMN * slot, _lane(g, i))
	if m["role"] == "donkey":
		var rng := RandomNumberGenerator.new()
		rng.seed = int(m["seed"])
		var k := CosmosFauna.species("donkey", rng)
		var c := CosmosCreature.new()
		c.cosmos = cosmos
		c.setup(k, pl, int(m["seed"]))
		c.set_meta("goods", m["goods"])
		c.set_meta("loot_title", "pack donkey")
		c.set_meta("caravan", g["id"])
		world.add_child(c)
		c.global_position = pl.global_position + local
		if float(m["hp"]) > 0.0:
			c.hp = float(m["hp"])
		cosmos.creatures.append(c)
		g["nodes"][i] = c
		return
	var t := CosmosTraveller.new()
	t.cosmos = cosmos
	t.traveller(pl, str(m["role"]), str(g["empire"]), int(m["seed"]))
	t.group = g
	t.goods = m["goods"]
	t.speed = float(g["speed"])
	if float(m["hp"]) > 0.0:
		t.hp = float(m["hp"])
	world.add_child(t)
	t.global_position = pl.global_position + local
	cosmos.npcs.append(t)
	g["nodes"][i] = t


## Its place in the column (0 the front) and its side of the road.
static func _slot(g: Dictionary, i: int) -> float:
	return float(i) * (0.55 if g["kind"] == "pilgrims" else 1.0)


static func _lane(g: Dictionary, i: int) -> float:
	if g["kind"] == "pilgrims":
		return -0.8 if i % 2 == 0 else 0.8
	return -0.7 if i % 2 == 0 else 0.7


## Each frame, a group that's out: along its road while all's well (the column
## kept together), halted while it fights; its donkeys driven, the beasts at it,
## the raiders' ambush, what you see of it in the event log.
func _live(w: Dictionary, pl: CosmosPlanet, rl: Array, delta: float) -> void:
	for g in w["groups"]:
		if not g["out"]:
			continue
		var nodes: Array = g["nodes"]
		var fight := false
		var lag := 0.0
		var alive := 0
		for i in nodes.size():
			var n = nodes[i]
			if n == null:
				continue
			if not is_instance_valid(n):
				nodes[i] = null
				continue
			var m: Dictionary = g["members"][i]
			if n.get("dead"):
				if not m["dead"]:
					m["dead"] = true
					_say(g, "A %s of the %s is killed" % [_who(m), str(g["title"])], "kill:%d" % i)
				continue
			if m["role"] != "donkey":
				alive += 1
				if n.get("threat") != null:
					fight = true
			var goal: Vector3 = n.get("goal") if n is CosmosTraveller else Vector3.INF
			if goal != Vector3.INF:
				lag = maxf(lag, (n as Node3D).global_position.distance_to(goal))
		var queued := _queue.any(func(q): return is_same(q[0], g))
		if alive == 0 and not queued:
			if (g["members"] as Array).any(func(m): return m["dead"] and m["role"] != "donkey"):
				_say(g, "The %s is wiped out - its goods lie in the road" % str(g["title"]), "wiped")
			_put_away(g)
			continue
		g["raiders"] = (g["raiders"] as Array).filter(func(r): return is_instance_valid(r))
		var raiders_up := (g["raiders"] as Array).filter(func(r): return not r.get("dead")).size()
		if g["raid"] and raiders_up == 0 and not _queue.any(func(q): return is_same(q[0], g) and q[1] < 0):
			g["raid"] = false
			_say(g, "The %s drives off its raiders" % str(g["title"]), "won")
		fight = fight or raiders_up > 0
		# Along the road, the column kept together (the slowest not left behind).
		if not fight and not queued:
			if float(g["halt"]) > 0.0:
				g["halt"] = float(g["halt"]) - delta
			else:
				var rate := 1.0 if lag < 3.0 else (0.35 if lag < 7.0 else 0.0)
				var L := float(rl[g["road"]]["length"])
				g["s"] = float(g["s"]) + int(g["dir"]) * float(g["speed"]) * rate * delta
				if (int(g["dir"]) > 0 and float(g["s"]) >= L) or (int(g["dir"]) < 0 and float(g["s"]) <= 0.0):
					g["s"] = clampf(float(g["s"]), 0.0, L)
					_arrive(w, g, pl, rl)
		for i in nodes.size():
			var n = nodes[i]
			if n == null or not is_instance_valid(n) or n.get("dead"):
				continue
			var local := where(pl, rl, g, float(g["s"]) - int(g["dir"]) * COLUMN * _slot(g, i), _lane(g, i))
			var goal := pl.global_position + local
			if n is CosmosTraveller:
				(n as CosmosTraveller).goal = goal
			else:
				_drive(n, goal, 0.0 if fight else float(g["speed"]))
		# The raiders' ambush, if one's coming.
		if float(g["ambush"]) > 0.0 and not fight:
			g["ambush"] = float(g["ambush"]) - delta
			if float(g["ambush"]) <= 0.0:
				_ambush(g, pl, rl)
		_beasts(g, nodes)


func _who(m: Dictionary) -> String:
	return {"guard": "guard", "trader": "trader", "donkey": "pack donkey", "courier": "courier", "pilgrim": "pilgrim"}.get(m["role"], "traveller")


## A note in the event log (once each thing a group: `key`).
func _say(g: Dictionary, text: String, key: String) -> void:
	if (g["seen"] as Dictionary).has(key):
		return
	g["seen"][key] = true
	if cosmos and cosmos.get("hud"):
		cosmos.hud.flash(text, 3.5)
	else:
		GameLog.post(text, "info")


## A donkey led to `goal` (CosmosCreature: its own wandering held off - idle, its
## velocity set here; it walks, its gait from that).
func _drive(c: Node, goal: Vector3, speed: float) -> void:
	var cr := c as CosmosCreature
	if cr == null or cr.dead:
		return
	cr.state = "idle"
	cr._t = 5.0
	var u := cr.up()
	var to := goal - cr.global_position
	to -= u * to.dot(u)
	var d := to.length()
	cr.velocity = to / d * clampf(d * 1.2, 0.0, maxf(speed * 1.8, 0.5)) if d > 0.4 and speed > 0.0 else Vector3.ZERO


## Raiders out of the nearest camp's side of the road, running in.
func _ambush(g: Dictionary, pl: CosmosPlanet, rl: Array) -> void:
	g["raid"] = true
	g["raided"] = true
	var at := where(pl, rl, g, float(g["s"]))
	var u := at.normalized()
	var camp := _camp_near(pl, at)
	var side: Vector3
	if camp != Vector3.INF:
		side = camp - at
		side -= u * side.dot(u)
	if camp == Vector3.INF or side.length() < 1.0:
		side = u.cross(Vector3.UP if absf(u.y) < 0.9 else Vector3.RIGHT).rotated(u, _rng.randf() * TAU)
	side = side.normalized()
	var n := _rng.randi_range(2, 4)
	for k in n:
		var off := side.rotated(u, _rng.randf_range(-0.5, 0.5)) * _rng.randf_range(48.0, 66.0)
		_queue.append([g, -1, pl, at + off])
	_say(g, "Raiders from a pirates' camp fall on the %s!" % str(g["title"]), "raid")


## The hunting beasts near a group go for its people (yours to deal with if they're
## hunting you: then left to their own) - driven at the nearest, their bites dealt here.
func _beasts(g: Dictionary, nodes: Array) -> void:
	var w: Node3D = cosmos.walker
	var lead: Node3D = null
	for n in nodes:
		if n != null and is_instance_valid(n) and not n.get("dead"):
			lead = n
			break
	if lead == null:
		return
	for c in cosmos.creatures:
		if not is_instance_valid(c) or c.dead or c.kind.get("temper") != "predator" or c.has_meta("caravan"):
			continue
		if c.global_position.distance_to(lead.global_position) > 48.0:
			continue
		var sight := 38.0 * (1.4 if c.kind.get("monster", false) else 1.0)
		if w and w.get("deck") == null and not w.get("downed") and c.global_position.distance_to(w.global_position) < sight * 1.1:
			continue   # (it's after you)
		var prey: Node3D = null
		var pd := INF
		for n in nodes:
			if n == null or not is_instance_valid(n) or n.get("dead"):
				continue
			var d: float = (n as Node3D).global_position.distance_to(c.global_position)
			if d < pd:
				pd = d
				prey = n
		if prey == null:
			continue
		_say(g, "A %s attacks the %s!" % [CosmosFauna.label(c.kind).to_lower() if c.kind.has("id") else str(c.kind["name"]), str(g["title"])], "beast:%d" % c.get_instance_id())
		c.state = "idle"
		c._t = 3.0
		var u: Vector3 = c.up()
		var to: Vector3 = prey.global_position - c.global_position
		to -= u * to.dot(u)
		var bite_at: float = float(c.reach) + 1.0
		c.velocity = to.normalized() * float(c.kind["run"]) if to.length() > bite_at else Vector3.ZERO
		if to.length() > 0.1:
			c.facing = to.normalized()
		var id: int = c.get_instance_id()
		_bites[id] = float(_bites.get(id, 0.0)) - get_process_delta_time()
		if to.length() <= bite_at + 0.3 and float(_bites[id]) <= 0.0:
			_bites[id] = 1.2
			prey.hurt(float(c.kind["bite"]), c.global_position)


func _exit_tree() -> void:
	for key in _worlds:
		for g in _worlds[key]["groups"]:
			g["out"] = false
			g["nodes"] = []
			g["raiders"] = []
	_queue.clear()
