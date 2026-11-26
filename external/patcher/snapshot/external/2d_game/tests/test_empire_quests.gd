extends TestCase
## The empires' main quests (tools/empire_quests.py -> data/scenarios.json):
## each is played from the capital to the end with its walkthrough, through
## the real rules engine (Scenarios) and a stand-in for the space scene's
## ScenarioHost - every step reachable, every ship countable, every delivery
## taken, rewards and the encyclopedia given, the quest finished. Also: the
## places they name exist, their monsters and ships exist, their text reads
## well, and leaving a system with a quest's enemies alive doesn't strand it.

const EMPIRES := ["athens", "sparta", "mycenae", "ionia", "cyclades"]


## The world, as far as the rules can see it.
class FakeHost extends Node:
	var pos = Vector2.ZERO
	var places := {}            # place -> Vector2 (in the current system)
	var items := {}
	var money := 0
	var dialogue := []
	var lore := []
	var spawned := {}           # "id:group" -> ships spawned
	var messages := []

	func player_position() -> Variant:
		return pos

	func place_position(_id: String, place: String) -> Variant:
		return places.get(place)

	func item_count(item: String) -> int:
		return int(items.get(item, 0))

	func credits() -> int:
		return money

	func objectives_changed() -> void:
		pass

	func play_dialogue(lines: Array) -> void:
		dialogue.append_array(lines)

	func message(text: String) -> void:
		messages.append(text)

	func give_item(item: String, count: int) -> void:
		items[item] = int(items.get(item, 0)) + count

	func take_item(item: String, count: int) -> void:
		items[item] = int(items.get(item, 0)) - count

	func add_credits(amount: int) -> void:
		money += amount

	func spawn_pending(id: String, _arrived := false) -> void:
		for r in Scenarios.state[id].get("spawns", []):
			if int(r["left"]) > 0 and r["system"] == "" and places.has(r["place"]):
				r["system"] = Galaxy.current_system
				var k := "%s:%s" % [id, r["group"]]
				spawned[k] = int(spawned.get(k, 0)) + int(r["left"])

	func drop_pending(_id: String, _arrived := false) -> void:
		pass

	func markers_changed(_id: String) -> void:
		pass

	func unlock_lore(lore_id: String) -> void:
		lore.append(lore_id)


var _host: FakeHost
var _old_system := ""


func setup() -> void:
	Galaxy.new_game(false)
	_old_system = Galaxy.current_system
	Scenarios.reload()
	Scenarios.state = {}
	_host = FakeHost.new()
	tree.root.add_child(_host)
	Scenarios.host = _host


func teardown() -> void:
	Scenarios.host = null
	Scenarios.state = {}
	_host.queue_free()
	Galaxy.current_system = _old_system


## Plays quest `id` through with its walkthrough; returns the problems.
func _play(id: String) -> Array:
	var sc := Scenarios.find(id)
	var out := []
	Scenarios.start(id)
	var walk: Array = sc.get("walkthrough", [])
	for i in walk.size():
		var w: Dictionary = walk[i]
		var before: String = Scenarios.state[id]["step"]
		if w.has("system"):
			Galaxy.current_system = str(w["system"])
		if w.has("give"):
			for it in w["give"]:
				_host.items[it] = int(_host.items.get(it, 0)) + int(w["give"][it])
		if w.has("near"):
			_host.places = {str(w["near"]): Vector2(1000, 0)}
			_host.pos = Vector2.ZERO
			Scenarios.tick(0.1)
			_host.pos = Vector2(1000, 0)
			Scenarios.tick(0.1)
		elif w.has("kill"):
			# (its place is here: what was ordered spawns; then every ship falls)
			var gname := str(w["kill"])
			for r in Scenarios.state[id]["spawns"]:
				if r["group"] == gname:
					_host.places[r["place"]] = Vector2(500, 0)
			_host.spawn_pending(id, true)
			var k := "%s:%s" % [id, gname]
			if int(_host.spawned.get(k, 0)) != int(w["count"]):
				out.append("walk %d: %d ships spawned for %s, expected %d" % [i, int(_host.spawned.get(k, 0)), gname, int(w["count"])])
			var recs: Array = Scenarios.state[id]["spawns"]
			for ri in recs.size():
				if recs[ri]["group"] == gname:
					for n in int(recs[ri]["left"]):
						Scenarios.group_ship_lost(id, gname, ri)
		else:
			Scenarios.event(str(w["event"]), w.get("args", {}))
		var after: String = Scenarios.state[id]["step"]
		if after == before and Scenarios.state[id]["status"] == "active":
			out.append("walk %d (%s) didn't move the quest on from '%s'" % [i, w, before])
			break
	if Scenarios.state[id]["status"] != "finished":
		out.append("not finished: at '%s'" % Scenarios.state[id]["step"])
	return out


func test_every_empire_has_a_quest() -> void:
	var by := {}
	for sc in Scenarios.all():
		if str(sc.get("id", "")).begins_with("empire_"):
			by[str(sc.get("empire", ""))] = sc
	for e in EMPIRES:
		check(by.has(e), "the %s have a main quest" % Galaxy.empire_name(e))
		if by.has(e):
			check(bool(by[e].get("enabled", false)), "%s's quest is on" % e)
			check(Scenarios.check(by[e]).filter(func(p): return not p.begins_with("Note")).is_empty(), "%s: %s" % [e, Scenarios.check(by[e])])


func test_each_quest_plays_to_the_end() -> void:
	for e in EMPIRES:
		setup()
		var id: String = "empire_" + e
		var problems := _play(id)
		check(problems.is_empty(), "%s: %s" % [id, problems.slice(0, 3)])
		check(_host.money > 3000, "%s pays its way (%d credits)" % [id, _host.money])
		check(int(_host.items.get("data_core", 0)) >= 3, "%s gives Data Cores (%d)" % [id, int(_host.items.get("data_core", 0))])
		check(_host.lore.size() >= 2, "%s unlocks its encyclopedia entries (%s)" % [id, _host.lore])
		for l in _host.lore:
			check(QuestData.LORE.has(l), "%s: the entry '%s' exists" % [id, l])
		check(_host.dialogue.size() >= 25, "%s tells a story (%d lines)" % [id, _host.dialogue.size()])
		for t in ["food", "water", "medicine", "weapons", "luxury_goods", "iron_ore", "titanium_ore", "platinum_ore", "electronics", "energy_cell"]:
			check(int(_host.items.get(t, 0)) >= 0, "%s takes no more %s than you bring" % [id, t])
		teardown()


## Every station, planet, gate and system the quests name is in the galaxy;
## every ship type exists and is hostile.
func test_quest_places_exist() -> void:
	var stations := {}
	for sid in Galaxy.stations:
		stations[str(Galaxy.stations[sid].get("name", ""))] = str(Galaxy.stations[sid].get("system", ""))
	for e in EMPIRES:
		var sc := Scenarios.find("empire_" + e)
		for r in sc.get("rules", []):
			var ev: Dictionary = r.get("when", {})
			var st := str(ev.get("args", {}).get("station", ""))
			if st != "":
				check(stations.has(st), "%s: station '%s' exists" % [e, st])
			for c in r.get("if", []):
				if c.get("cond") == "in_system":
					check(Galaxy.systems.has(str(c["args"]["system"])), "%s: system %s exists" % [e, c["args"]["system"]])
			for a in r.get("then", []):
				if a.get("action") == "spawn":
					check(EnemyTypes.has_type(str(a["args"]["ship_type"])), "%s: ship type %s exists" % [e, a["args"]["ship_type"]])
					check(EnemyTypes.get_type(str(a["args"]["ship_type"])).get("faction", "enemy") == "enemy", "%s: %s is hostile" % [e, a["args"]["ship_type"]])
		for w in sc.get("walkthrough", []):
			if not w.has("system"):
				continue
			var sysd: Dictionary = Galaxy.system(str(w["system"]))
			var place := str(w.get("near", ""))
			if place == "" and w.has("kill"):
				for r in sc["rules"]:
					for a in r.get("then", []):
						if a.get("action") == "spawn" and a["args"]["group"] == w["kill"]:
							place = str(a["args"]["place"])
			var kind := place.get_slice(":", 0)
			var arg := place.substr(kind.length() + 1)
			match kind:
				"planet":
					var names: Array = sysd.get("planets", []).map(func(p): return str(p.get("name", "")) if p is Dictionary else str(p))
					check(names.has(arg), "%s: planet %s is in %s" % [e, arg, w["system"]])
				"gate":
					check(Galaxy.systems[str(w["system"])].get("gates", {}).has(arg), "%s: %s has a gate to %s" % [e, w["system"], arg])
				"station":
					check(stations.get(arg, "") == str(w["system"]) or stations.has(arg), "%s: station %s exists" % [e, arg])


## The way the stories are told: no modern words, every speaker named, each
## quest with its invocation of the Muse.
func test_quests_read_like_old_stories() -> void:
	var modern := ["okay", "ok", "cool", "guys", "yeah", "awesome", "lol", "hey", "dude", "gonna", "wanna", "hi-tech", "sci-fi", "kid", "stuff", "folks"]
	for e in EMPIRES:
		var sc := Scenarios.find("empire_" + e)
		var all_text := ""
		var muse := false
		for r in sc.get("rules", []):
			for a in r.get("then", []):
				if a.get("action") == "dialogue":
					for l in a["args"]["lines"]:
						check(str(l[0]) != "", "%s: every line has a speaker" % e)
						all_text += " " + str(l[1]).to_lower()
						if str(l[1]).begins_with("Sing, Muse"):
							muse = true
		check(muse, "%s: the story opens with the Muse" % e)
		var words := {}
		for w in all_text.replace(".", " ").replace(",", " ").replace("!", " ").replace("?", " ").replace(";", " ").replace(":", " ").replace("'", " ").split(" ", false):
			words[w] = true
		for w in modern:
			check(not words.has(w), "%s: no modern word '%s'" % [e, w])


## A quest's enemies in another system wait there; leaving a system with
## them alive brings them back when you return (the quest never strands).
func test_quest_enemies_wait_in_their_system() -> void:
	var id := "empire_sparta"
	Scenarios.start(id)
	Galaxy.current_system = "kyros"
	Scenarios.event("docked", {"station": "Sparta Barracks"})   # (the prologue; the first fight's ships ordered)
	var recs: Array = Scenarios.state[id]["spawns"]
	check(recs.size() == 2 and recs.all(func(r): return r["system"] == ""), "ordered for a gate not here yet: none out (%s)" % [recs])
	_host.places = {"gate:pylos": Vector2(800, 0)}
	_host.spawn_pending(id, true)
	check(recs.all(func(r): return r["system"] == "kyros"), "arriving where the gate is: they come out there")
	Scenarios.group_ship_lost(id, "g1", 0)   # one of three falls, then you jump away and back
	check(int(recs[0]["left"]) == 1, "the fallen one is counted")
	check(Scenarios.state[id]["step"].begins_with("1 "), "still on the fight")
	for ri in recs.size():
		for n in int(recs[ri]["left"]):
			Scenarios.group_ship_lost(id, "g1", ri)
	check(Scenarios.state[id]["step"].begins_with("2 "), "all three down: the quest moves on (%s)" % Scenarios.state[id]["step"])


## An old save (made before these quests existed) gets them, from their beginning.
func test_old_saves_get_the_quests() -> void:
	Scenarios.load_save_data({"missing_freighter": {"status": "not started", "step": ""}})
	for e in EMPIRES:
		check(Scenarios.state.has("empire_" + e) and Scenarios.state["empire_" + e]["status"] == "active", "%s's quest waits in an old save" % e)
		check(Scenarios.state["empire_" + e]["step"] == "Not started", "%s's from its start" % e)


## Kilon Alios has something to say of every people, and the story of New Hellas.
func test_kilon_tells_of_every_people() -> void:
	var emp: Dictionary = QuestData.GIVER.get("empires", {})
	for e in Galaxy.MAJOR + ["pirates", "independent"]:
		check(emp.has(e), "Kilon speaks of the %s" % Galaxy.empire_name(e))
		if emp.has(e):
			check(not (emp[e].get("greeting", []) as Array).is_empty(), "%s: his greeting there" % e)
			check((emp[e].get("topics", []) as Array).size() >= (3 if e in Galaxy.MAJOR else 1), "%s: his topics there" % e)
	check((QuestData.GIVER.get("hellas", []) as Array).size() >= 5, "the story of New Hellas, in parts")
	# And he tells the empires' stories himself.
	for e in EMPIRES:
		var speakers := {}
		for r in Scenarios.find("empire_" + e).get("rules", []):
			for a in r.get("then", []):
				if a.get("action") == "dialogue":
					for l in a["args"]["lines"]:
						speakers[str(l[0])] = true
		check(speakers.has("Kilon Alios"), "%s: Kilon Alios tells it" % e)


## On a world the Athenians hold: Kilon is there and speaks of them, the
## buildings are Athenian (named, materials, their own furniture).
func test_an_athenian_world() -> void:
	var was := Galaxy.current_system
	Galaxy.current_system = "nyx"   # (Athenai)
	SaveGame.space_state = {}
	SaveGame.landed_planet = "selene"   # (not Amnissos, Kilon's home world)
	var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
	tree.root.add_child(s)
	while not s.is_built:
		await tree.process_frame
	check_eq(s.culture(), "athens", "the planet's culture: its system's owner")
	check(s.quest_giver != null, "Kilon Alios stands by the landing pad")
	check(not s.quest_giver.offering, "no quest sign over him away from Amnissos")
	var topics: Array = s._giver_culture().get("topics", [])
	check(topics.size() >= 3 and str(topics[0]["ask"]).contains("Athenians"), "he speaks of the Athenians")
	var names: Array = s.buildings.map(func(b): return str(b.title))
	check(names.any(func(n): return n.begins_with("Athenian")), "Athenian buildings: %s" % [names])
	check(s._furniture_for("palace").has("owl"), "Athena's owl among the furniture")
	check(not s._furniture_for("temple").has("goddess") and not s._furniture_for("temple").has("labrys"), "no Minoan snake goddess or double axe in an Athenian temple")
	check(MinoanTiles.style("palace") == MinoanTiles.STYLES["athens_palace"], "Athenian buildings of their own (not the Minoan pieces)")
	check(s._building_skin == null, "no recolouring over their own art")
	var people := s.find_children("*", "", true, false).filter(func(n): return n is SurfaceProps.MinoanNpc and not n is SurfaceProps.QuestGiver)
	var rigs := {}
	for n in people:
		rigs[n.rig_name] = int(rigs.get(n.rig_name, 0)) + 1
	rigs.erase("pirate")   # (raiders come to every world)
	check(rigs.keys() == ["athenian"], "the citizens are Athenians: %s" % [rigs])
	check(Furniture.picture("chair", "ne")[0].resource_path.contains("/athens/"), "Athenian furniture")
	s.queue_free()
	await tree.process_frame
	Galaxy.current_system = was
	SaveGame.landed_planet = ""


## The empires' furniture, drawn in code: each piece draws (against either wall).
func test_empire_furniture_draws() -> void:
	for k in ["owl", "krater", "shield_rack", "lion_relief", "ionic_column", "star_globe", "idol"]:
		for w in ["nw", "ne"]:
			var f: Furniture = Furniture.new().setup(k, w, Vector2i(3, 3), Vector2(100, 100), "palace")
			tree.root.add_child(f)
			check(f.texture == null and f.height > 30.0, "%s: drawn in code, %d px tall" % [k, f.height])
			f.queue_redraw()
			await tree.process_frame
			check_eq(f.display_name(), Furniture.KINDS[k][0], "%s: its name" % k)
			f.queue_free()


## Every building style (the Minoans' and the empires' own) has every part a
## building needs, and every piece it names is drawn (data/sprites).
func test_building_styles_complete() -> void:
	for st in MinoanTiles.STYLES:
		var d: Dictionary = MinoanTiles.STYLES[st]
		for k in ["plain", "window", "door", "floor", "mosaic", "roof", "column", "caps", "antenna", "dome", "horns", "decor", "entrance"]:
			check(d.has(k), "%s has its %s" % [st, k])
		check((d.get("caps", []) as Array).size() >= 3, "%s: a cap for each of the roof's 3 corners" % st)
		check((d.get("entrance", []) as Array).size() >= 2, "%s: two pieces by the door" % st)
		var pieces: Array = d["floor"] + d["mosaic"] + d["roof"] + d["caps"] + d["decor"] + d["entrance"] + [d["column"], d["antenna"], d["dome"], d["horns"]]
		for design in d["plain"] + d["window"] + [d["door"]]:
			for o in ["x", "y"]:
				pieces.append(MinoanTiles._wall_piece(design, o))
		for p in pieces:
			check(ResourceLoader.exists("res://data/sprites/tile_%s.png" % p), "%s: its piece %s is drawn" % [st, p])


## Every empire's worlds are its own: on a planet it holds, its buildings,
## its people and its furniture (none of the Minoans'), Kilon by the pad.
func test_every_empire_world_is_its_own() -> void:
	var holds := {"athens": "nyx", "sparta": "kyros", "mycenae": "naxos", "ionia": "miletos", "cyclades": "g40_delos"}
	var rigs := {"athens": "athenian", "sparta": "spartan", "mycenae": "mycenaean", "ionia": "ionian", "cyclades": "cycladic"}
	var was := Galaxy.current_system
	for e in holds:
		Galaxy.current_system = holds[e]
		SaveGame.space_state = {}
		SaveGame.landed_planet = "selene"
		var s: Node = load("res://scenes/planet_surface.tscn").instantiate()
		tree.root.add_child(s)
		while not s.is_built:
			await tree.process_frame
		check_eq(s.culture(), e, "%s holds the world" % e)
		check(MinoanTiles.style("temple") == MinoanTiles.STYLES[e + "_temple"], "%s: its own temples" % e)
		check(s._building_skin == null, "%s: no recolouring" % e)
		var found := {}
		for n in s.find_children("*", "", true, false):
			if n is SurfaceProps.MinoanNpc and n.rig_name != "pirate":
				found[n.rig_name] = true
		check(found.keys() == [rigs[e]], "%s: its own people (%s)" % [e, found.keys()])
		check(Furniture.picture("bed", "ne")[0].resource_path.contains("/%s/" % e), "%s: its own furniture" % e)
		check(s.quest_giver != null, "%s: Kilon by the pad" % e)
		s.queue_free()
		await tree.process_frame
	Galaxy.current_system = was
	SaveGame.landed_planet = ""
