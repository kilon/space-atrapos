class_name Scenarios
## Quest scenarios written as plain-sentence rules (data/scenarios.json):
##   WHEN <event> AND <condition> AND ... THEN <action>, <action>, ...
## A scenario has named steps (Not started -> ... -> Finished); rules usually
## test "the quest step is ...", and actions move it on. This class holds the
## definitions of every event, condition and action (with their sentences and
## argument types - the Scenario Editor builds its drop-downs from them), the
## scenarios, and the runtime state (kept across scenes and in save games).
## Things that need the world (spawning ships, markers, dialogue, the HUD) go
## through `host`: the space scene's ScenarioHost (on a planet: logged only).

const FILE := "res://data/scenarios.json"

## Argument types: station, system, planet, item, ship_type, empire, state,
## step, scenario, number, text, lines (dialogue), place, group, marker,
## timer, var, op, beacon, lore, tier.

## Events: id -> [sentence, {arg: type}]. {arg} in the sentence marks where
## the argument goes.
const EVENTS := {
	"start": ["the scenario starts", {}],
	"step": ["the quest reaches step {step}", {"step": "step"}],
	"docked": ["the player docks at {station}", {"station": "station"}],
	"entered": ["the player arrives in the {system} system", {"system": "system"}],
	"landed": ["the player lands on {planet}", {"planet": "planet"}],
	"near": ["the player comes within {distance} m of {place}", {"distance": "number", "place": "place"}],
	"killed": ["the player destroys a {ship_type}", {"ship_type": "ship_type"}],
	"group_gone": ["every ship of group {group} is destroyed", {"group": "group"}],
	"picked": ["the player picks up {item}", {"item": "item"}],
	"has": ["the player has {count} {item}", {"count": "number", "item": "item"}],
	"timer": ["timer {timer} runs out", {"timer": "timer"}],
	"talked": ["the player talks to a citizen on {planet}", {"planet": "planet"}],
	"every": ["every {seconds} seconds", {"seconds": "number"}],
}

## Conditions: id -> [sentence, {arg: type}].
const CONDITIONS := {
	"step_is": ["the quest step is {step}", {"step": "step"}],
	"step_not": ["the quest step is not {step}", {"step": "step"}],
	"has_item": ["the player has at least {count} {item}", {"count": "number", "item": "item"}],
	"lacks_item": ["the player has fewer than {count} {item}", {"count": "number", "item": "item"}],
	"credits": ["the player has at least {amount} drachmas", {"amount": "number"}],
	"in_system": ["the player is in the {system} system", {"system": "system"}],
	"system_state": ["the current system is in {state}", {"state": "state"}],
	"owner": ["the current system belongs to the {empire}", {"empire": "empire"}],
	"reputation": ["reputation with the {empire} is {op} {value}", {"empire": "empire", "op": "op", "value": "number"}],
	"standing": ["your standing with the {empire} is at least {tier}", {"empire": "empire", "tier": "tier"}],
	"chapter": ["the main story's stage is {op} {value}", {"op": "op", "value": "number"}],
	"var": ["counter {var} is {op} {value}", {"var": "var", "op": "op", "value": "number"}],
	"chance": ["a random chance of {percent} % comes up", {"percent": "number"}],
	"scenario": ["scenario {scenario} is {status}", {"scenario": "scenario", "status": "status"}],
}

## Actions: id -> [sentence, {arg: type}].
const ACTIONS := {
	"set_step": ["move the quest to step {step}", {"step": "step"}],
	"objective": ["show the objective \"{text}\"", {"text": "text"}],
	"clear_objective": ["clear the objective", {}],
	"dialogue": ["play the dialogue {lines}", {"lines": "lines"}],
	"message": ["show the message \"{text}\"", {"text": "text"}],
	"give_item": ["give the player {count} {item}", {"count": "number", "item": "item"}],
	"take_item": ["take {count} {item} from the player", {"count": "number", "item": "item"}],
	"credits": ["give the player {amount} drachmas", {"amount": "number"}],
	"take_credits": ["take {amount} drachmas from the player", {"amount": "number"}],
	"reputation": ["change reputation with the {empire} by {amount}", {"empire": "empire", "amount": "number"}],
	"spawn": ["spawn {count} {ship_type} as group {group} at {place}", {"count": "number", "ship_type": "ship_type", "group": "group", "place": "place"}],
	"marker": ["place marker {marker} ({beacon}) at {place}", {"marker": "marker", "beacon": "beacon", "place": "place"}],
	"remove_marker": ["remove marker {marker}", {"marker": "marker"}],
	"drop_item": ["leave {item} floating at {place}", {"item": "item", "place": "place"}],
	"timer": ["start timer {timer} for {seconds} seconds", {"timer": "timer", "seconds": "number"}],
	"set_var": ["set counter {var} to {value}", {"var": "var", "value": "number"}],
	"add_var": ["add {value} to counter {var}", {"value": "number", "var": "var"}],
	"lore": ["unlock the encyclopedia entry {lore}", {"lore": "lore"}],
	"start_scenario": ["start scenario {scenario}", {"scenario": "scenario"}],
	"finish": ["finish the scenario (success)", {}],
	"fail": ["fail the scenario", {}],
}

const OPS := ["=", "!=", "<", "<=", ">", ">="]
const STATUSES := ["active", "finished", "failed", "not started"]
const BEACONS := ["signal", "thread", "none"]

static var _data := {}
static var _loaded := false
## Runtime state: scenario id -> {status, step, vars, timers, fired, markers,
## groups, objective, every}.
static var state := {}
## The current scene's world access (ScenarioHost), or null.
static var host: Node
## Test runs: {id, step} applied when the next game starts.
static var test_request := {}


# --- Data ---------------------------------------------------------------------------

static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_data = DataFiles.read(FILE)
	if not _data.has("scenarios"):
		_data = {"scenarios": []}


static func reload() -> void:
	_loaded = false
	_load()
	_stamp = _file_stamp()


## Reads the file again only if it changed since it was last read (the
## Scenario Editor opening: ~25 ms of JSON otherwise, on every visit).
static var _stamp := ""

static func reload_if_changed() -> void:
	if not _loaded or _file_stamp() != _stamp:
		reload()


static func _file_stamp() -> String:
	var parts := []
	for p in [DataFiles.user_path(FILE), FILE]:
		parts.append(str(FileAccess.get_modified_time(p)) if FileAccess.file_exists(p) else "-")
	return ",".join(parts)


static func all() -> Array:
	_load()
	return _data["scenarios"]


static func find(id: String) -> Dictionary:
	for s in all():
		if s.get("id") == id:
			return s
	return {}


static func save() -> String:
	_load()
	_data["_help"] = "Quest scenarios: rules WHEN event AND conditions THEN actions. Edit them in Talos > Scenario Editor."
	return DataFiles.write(FILE, _data)


## A new, empty scenario.
static func blank(id: String, title: String) -> Dictionary:
	return {"id": id, "title": title, "description": "", "enabled": true, "steps": ["Not started", "Finished"], "rules": []}


static func blank_rule(step := "") -> Dictionary:
	var r := {"when": {"event": "docked", "args": {}}, "if": [], "then": [], "once": true, "note": ""}
	if step != "":
		r["if"].append({"cond": "step_is", "args": {"step": step}})
	return r


## The sentence of an event / condition / action with its arguments filled in.
static func sentence(table: Dictionary, id: String, args: Dictionary) -> String:
	if not table.has(id):
		return "(unknown: %s)" % id
	var s: String = table[id][0]
	for a in table[id][1]:
		var v = args.get(a, "?")
		if v is Array:
			v = "(%d lines)" % v.size()
		s = s.replace("{%s}" % a, str(v))
	return s


## Problems with a scenario: unknown steps, steps nothing leads to, rules
## without actions, items taken but never given...
static func check(sc: Dictionary) -> Array:
	var out := []
	var steps: Array = sc.get("steps", [])
	var reached := {steps[0]: true} if not steps.is_empty() else {}
	var given := {}
	var taken := {}
	var groups_made := {}
	var markers_made := {}
	var rules: Array = sc.get("rules", [])
	for i in rules.size():
		var r: Dictionary = rules[i]
		var label := "Rule %d" % (i + 1)
		if (r.get("then", []) as Array).is_empty():
			out.append("%s does nothing (no THEN actions)." % label)
		var ev: Dictionary = r.get("when", {})
		if ev.get("event") == "group_gone":
			groups_made[ev.get("args", {}).get("group", "")] = groups_made.get(ev.get("args", {}).get("group", ""), false)
		for c in r.get("if", []):
			if c.get("cond") in ["step_is", "step_not"] and not steps.has(c.get("args", {}).get("step", "")):
				out.append("%s tests a step that doesn't exist: '%s'." % [label, c.get("args", {}).get("step", "")])
		if ev.get("event") == "step" and not steps.has(ev.get("args", {}).get("step", "")):
			out.append("%s waits for a step that doesn't exist: '%s'." % [label, ev.get("args", {}).get("step", "")])
		for a in r.get("then", []):
			var args: Dictionary = a.get("args", {})
			match a.get("action"):
				"set_step":
					if not steps.has(args.get("step", "")):
						out.append("%s moves to a step that doesn't exist: '%s'." % [label, args.get("step", "")])
					reached[args.get("step", "")] = true
				"give_item", "drop_item":
					given[args.get("item", "")] = true
				"take_item":
					taken[args.get("item", "")] = true
				"spawn":
					groups_made[args.get("group", "")] = true
				"marker":
					markers_made[args.get("marker", "")] = true
				"finish":
					if not steps.is_empty():
						reached[steps[-1]] = true
	for st in steps:
		if not reached.has(st):
			out.append("Nothing ever moves the quest to step '%s'." % st)
	for g in groups_made:
		if not groups_made[g]:
			out.append("A rule waits for group '%s' to be destroyed, but nothing spawns it." % g)
	for it in taken:
		if not given.has(it):
			out.append("Note: '%s' is taken from the player but no rule gives it - fine if they gather it themselves." % it)
	return out


# --- The main quest as rules ------------------------------------------------------------

## The main quest (QuestData stages) written as a rules scenario - a worked
## example of every kind of objective. Disabled: the story keeps its own runner
## (which also drives chapters, the journal and the Labyrinth's seal).
static func from_main_quest() -> Dictionary:
	var sc := blank("thread_of_ariadne_rules", "The Thread of Ariadne (as rules)")
	sc["enabled"] = false
	sc["description"] = "The main quest, converted to rules from data/main_quest.json: one step per stage. Enable it only if you turn the built-in story off - otherwise both run."
	var stages: Array = QuestData.STAGES
	var names: Array = ["Not started"]
	for i in stages.size():
		names.append("%d %s" % [i + 1, str(stages[i].get("objective", "stage")).left(34)])
	names.append("Finished")
	sc["steps"] = names
	var rules: Array = sc["rules"]
	var pt := func(v: Vector2) -> String: return "point:%d,%d" % [roundi(v.x), roundi(v.y)]
	rules.append({"when": {"event": "start", "args": {}}, "if": [], "then": [{"action": "set_step", "args": {"step": names[1]}}], "once": true, "note": "Begin"})
	for i in stages.size():
		var st: Dictionary = stages[i]
		var step: String = names[i + 1]
		var next: String = names[i + 2]
		var at_step := [{"cond": "step_is", "args": {"step": step}}]
		# Entering the step: objective, dialogue, world objects.
		var setup := [{"action": "objective", "args": {"text": str(st.get("objective", ""))}}]
		var lines: Array = st.get("dialogue", []).map(func(l): return [str(l[0]), str(l[1])])
		if not lines.is_empty():
			setup.append({"action": "dialogue", "args": {"lines": lines}})
		match st.get("type", ""):
			"reach":
				setup.append({"action": "marker", "args": {"marker": "stage%d" % i, "beacon": str(st.get("beacon", "none")), "place": pt.call(st["pos"])}})
			"kill":
				var k := 0
				for e in st.get("spawn", []):
					setup.append({"action": "spawn", "args": {"count": 1, "ship_type": str(e[0]), "group": "stage%d" % i, "place": pt.call(st["pos"] + e[1])}})
					k += 1
				if st.has("relic"):
					setup.append({"action": "drop_item", "args": {"item": str(st["relic"]), "place": pt.call(st["pos"])}})
			"pickup":
				setup.append({"action": "drop_item", "args": {"item": str(st["item"]), "place": pt.call(st["pos"])}})
		rules.append({"when": {"event": "step", "args": {"step": step}}, "if": [], "then": setup, "once": true, "note": "Stage %d begins" % (i + 1)})
		# Completing the step: rewards, lore, on to the next.
		var done := []
		var rw: Dictionary = st.get("reward", {})
		if rw.has("credits"):
			done.append({"action": "credits", "args": {"amount": int(rw["credits"])}})
		if rw.has("data_core"):
			done.append({"action": "give_item", "args": {"count": int(rw["data_core"]), "item": "data_core"}})
		if rw.has("equipment"):
			done.append({"action": "message", "args": {"text": "Reward: %s (equipment rewards aren't a rules action yet)" % str(rw["equipment"])}})
		for l in st.get("lore", []):
			done.append({"action": "lore", "args": {"lore": str(l)}})
		if st.get("type") == "reach":
			done.append({"action": "remove_marker", "args": {"marker": "stage%d" % i}})
		done.append({"action": "set_step", "args": {"step": next}})
		var when := {}
		var cond := at_step.duplicate(true)
		match st.get("type", ""):
			"dock":
				when = {"event": "docked", "args": {"station": str(st["station"])}}
			"reach":
				when = {"event": "near", "args": {"distance": float(st.get("radius", 300)), "place": pt.call(st["pos"])}}
				cond.append({"cond": "in_system", "args": {"system": Galaxy.HOME}})
			"kill":
				when = {"event": "group_gone", "args": {"group": "stage%d" % i}}
			"pickup":
				when = {"event": "picked", "args": {"item": str(st["item"])}}
			"deliver":
				when = {"event": "docked", "args": {"station": str(st["station"])}}
				var items: Dictionary = st.get("items", {})
				var takes := []
				for it in items:
					cond.append({"cond": "has_item", "args": {"count": int(items[it]), "item": str(it)}})
					takes.append({"action": "take_item", "args": {"count": int(items[it]), "item": str(it)}})
				done = takes + done
				rules.append({"when": when.duplicate(true), "if": at_step.duplicate(true), "then": [{"action": "message", "args": {"text": "Still needed: " + ", ".join(items.keys().map(func(k): return "%d %s" % [items[k], Items.display_name(k)]))}}],
					"once": false, "note": "Stage %d: reminder when something is missing" % (i + 1)})
			"end":
				done.pop_back()
				done.append({"action": "finish", "args": {}})
				when = {"event": "step", "args": {"step": step}}
		rules.append({"when": when, "if": cond if st.get("type") != "end" else [], "then": done, "once": true, "note": "Stage %d complete" % (i + 1)})
	return sc


# --- Runtime ---------------------------------------------------------------------------

static func _st(id: String) -> Dictionary:
	if not state.has(id):
		state[id] = {"status": "not started", "step": "", "vars": {}, "timers": {}, "fired": [], "markers": {},
			"groups": {}, "objective": "", "every": {}, "conds": {}, "spawns": [], "drops": []}
	return state[id]


## A new game: scenarios that are enabled start (their "the scenario starts"
## rules fire); a test run puts its scenario at the chosen step.
static func new_game() -> void:
	state = {}
	for sc in all():
		if bool(sc.get("enabled", true)) or test_request.get("id") == sc["id"]:
			start(sc["id"])
	if not test_request.is_empty():
		var id: String = test_request["id"]
		var step: String = test_request.get("step", "")
		if step != "":
			_set_step(id, step)
		test_request = {}


static func start(id: String) -> void:
	var sc := find(id)
	if sc.is_empty():
		return
	var s := _st(id)
	if s["status"] == "active":
		return
	s["status"] = "active"
	var steps: Array = sc.get("steps", [])
	s["step"] = steps[0] if not steps.is_empty() else ""
	# (announced only if it does something now: the empires' stories wait
	# quietly until you dock at their capitals)
	if (sc.get("rules", []) as Array).any(func(r): return r.get("when", {}).get("event", "") == "start"):
		_log("Scenario started: " + str(sc.get("title", id)))
	_fire(id, "start", {})


## The game reports an event (args per EVENTS); every active scenario's
## matching rules run.
static func event(name: String, args := {}) -> void:
	if name == "picked":   # (a scenario's dropped item taken: not dropped again)
		for id in state.keys():
			for d in state[id].get("drops", []):
				if not d["taken"] and d["item"] == str(args.get("item", "")) and d["system"] == Galaxy.current_system:
					d["taken"] = true
					break
	for id in state.keys():
		if state[id]["status"] == "active":
			_fire(id, name, args)


## Called every frame by the host: timers, "every N seconds" and the
## state-like events (near, has - those COND_EVERY).
static var _cond_t := 0.0
static var _cond_n := 0
const COND_EVERY := 0.05   # s: the state-like events checked 20 times a second -
const COND_FRAMES := 4     # or every 4th frame if that's sooner (every frame was ~0.2 ms)

## (At most RATE times a second, with the time since: going through every
## scenario's rules every frame at 600 FPS was ten times what timers need.)
const RATE := 120.0
static var _acc := 0.0

static func tick(delta: float) -> void:
	_acc += delta
	if _acc < 1.0 / RATE:
		return
	delta = _acc
	_acc = 0.0
	_cond_t += delta
	_cond_n += 1
	var check := _cond_t >= COND_EVERY or _cond_n >= COND_FRAMES
	if check:
		_cond_t = 0.0
		_cond_n = 0
	for id in state.keys():
		var s: Dictionary = state[id]
		if s["status"] != "active":
			continue
		for t in s["timers"].keys():
			s["timers"][t] = float(s["timers"][t]) - delta
			if s["timers"][t] <= 0.0:
				s["timers"].erase(t)
				_fire(id, "timer", {"timer": t})
		var sc := find(id)
		var rules: Array = sc.get("rules", [])
		for i in rules.size():
			var ev: Dictionary = rules[i].get("when", {})
			var e: String = ev.get("event", "")
			if e == "every":
				var k := str(i)
				s["every"][k] = float(s["every"].get(k, 0.0)) + delta
				if s["every"][k] >= maxf(float(ev.get("args", {}).get("seconds", 10)), 0.5):
					s["every"][k] = 0.0
					_run_rule(id, i, {})
			elif check and e in ["near", "has"]:
				# Fires when it becomes true (edge), not every frame while true.
				var now := _state_event_true(id, e, ev.get("args", {}))
				var k := "e%d" % i
				if now and not bool(s["conds"].get(k, false)):
					_run_rule(id, i, {})
				s["conds"][k] = now


static func _state_event_true(id: String, e: String, args: Dictionary) -> bool:
	match e:
		"near":
			if host == null or not host.has_method("player_position"):
				return false
			var p = host.call("place_position", id, str(args.get("place", "player")))
			var me = host.call("player_position")
			return p != null and me != null and (me as Vector2).distance_to(p) <= float(args.get("distance", 300))
		"has":
			return _count(str(args.get("item", ""))) >= int(args.get("count", 1))
	return false


static func _fire(id: String, name: String, args: Dictionary) -> void:
	var rules: Array = find(id).get("rules", [])
	for i in rules.size():
		var ev: Dictionary = rules[i].get("when", {})
		if ev.get("event") == name and _event_matches(name, ev.get("args", {}), args):
			_run_rule(id, i, args)


static func _event_matches(name: String, want: Dictionary, got: Dictionary) -> bool:
	for k in want:
		if k in ["distance", "seconds"]:
			continue
		var w := str(want[k])
		if w == "" or w == "any":
			continue
		if not got.has(k) or str(got[k]) != w:
			return false
	return true


static func _run_rule(id: String, i: int, _args: Dictionary) -> void:
	var s := _st(id)
	if s["status"] != "active":
		return
	var r: Dictionary = find(id)["rules"][i]
	if bool(r.get("once", true)) and (s["fired"] as Array).has(i):
		return
	for c in r.get("if", []):
		if not _test(id, c.get("cond", ""), c.get("args", {})):
			return
	if bool(r.get("once", true)):
		s["fired"].append(i)
	for a in r.get("then", []):
		if s["status"] != "active":
			break
		_do(id, a.get("action", ""), a.get("args", {}))


static func _cmp(a: float, op: String, b: float) -> bool:
	match op:
		"=": return is_equal_approx(a, b)
		"!=": return not is_equal_approx(a, b)
		"<": return a < b
		"<=": return a <= b
		">": return a > b
	return a >= b


static func _count(item: String) -> int:
	if host and host.has_method("item_count"):
		return int(host.call("item_count", item))
	return 0


static func _test(id: String, cond: String, a: Dictionary) -> bool:
	var s := _st(id)
	match cond:
		"step_is": return s["step"] == str(a.get("step", ""))
		"step_not": return s["step"] != str(a.get("step", ""))
		"has_item": return _count(str(a.get("item", ""))) >= int(a.get("count", 1))
		"lacks_item": return _count(str(a.get("item", ""))) < int(a.get("count", 1))
		"credits": return host != null and host.has_method("credits") and int(host.call("credits")) >= int(a.get("amount", 0))
		"in_system": return Galaxy.current_system == str(a.get("system", ""))
		"system_state": return Galaxy.state_of(Galaxy.current_system) == str(a.get("state", ""))
		"owner": return Galaxy.owner_of(Galaxy.current_system) == str(a.get("empire", ""))
		"reputation": return _cmp(float(Galaxy.reputation.get(str(a.get("empire", "")), 0.0)), str(a.get("op", ">=")), float(a.get("value", 0)))
		"standing":
			var tiers: Array = Galaxy.REP_TIERS.map(func(t): return t[0])
			return tiers.find(Galaxy.standing(str(a.get("empire", "")))) >= tiers.find(str(a.get("tier", "Neutral")))
		"chapter": return _cmp(float(Themes.chapter), str(a.get("op", ">=")), float(a.get("value", 0)))
		"var": return _cmp(float(s["vars"].get(str(a.get("var", "")), 0.0)), str(a.get("op", "=")), float(a.get("value", 0)))
		"chance": return randf() * 100.0 < float(a.get("percent", 50))
		"scenario": return _st(str(a.get("scenario", ""))).get("status") == str(a.get("status", "active"))
	return false


static func _set_step(id: String, step: String) -> void:
	var s := _st(id)
	if s["step"] == step:
		return
	s["step"] = step
	_fire(id, "step", {"step": step})


static func _do(id: String, action: String, a: Dictionary) -> void:
	var s := _st(id)
	var h := host
	match action:
		"set_step": _set_step(id, str(a.get("step", "")))
		"objective":
			s["objective"] = str(a.get("text", ""))
			if h: h.call("objectives_changed")
		"clear_objective":
			s["objective"] = ""
			if h: h.call("objectives_changed")
		"dialogue":
			if h: h.call("play_dialogue", _lines(a.get("lines", [])))
		"message":
			if h: h.call("message", str(a.get("text", "")))
			else: _log(str(a.get("text", "")))
		"give_item": if h: h.call("give_item", str(a.get("item", "")), int(a.get("count", 1)))
		"take_item": if h: h.call("take_item", str(a.get("item", "")), int(a.get("count", 1)))
		"credits": if h: h.call("add_credits", int(a.get("amount", 0)))
		"take_credits": if h: h.call("add_credits", -int(a.get("amount", 0)))
		"reputation": Galaxy.change_reputation(str(a.get("empire", "")), float(a.get("amount", 0)))
		"spawn":
			# (a record of what's still to destroy, and where: ships not in
			# the system you're in - or left behind when you jump away - come
			# out when you get there: ScenarioHost.spawn_pending)
			var g := str(a.get("group", "group"))
			s["groups"][g] = int(s["groups"].get(g, 0)) + int(a.get("count", 1))
			s["spawns"].append({"group": g, "ship_type": str(a.get("ship_type", "")), "place": str(a.get("place", "player")),
				"left": int(a.get("count", 1)), "system": ""})
			if h and h.has_method("spawn_pending"):
				h.call("spawn_pending", id)
			elif h:   # (an older host: spawns at once, where it is)
				h.call("spawn", id, g, str(a.get("ship_type", "")), int(a.get("count", 1)), str(a.get("place", "player")))
		"marker":
			# (its system: this one for a point; for a station / planet / gate,
			# the system that has it - found when you're there: ScenarioHost)
			var place := str(a.get("place", "player"))
			s["markers"][str(a.get("marker", ""))] = [place, str(a.get("beacon", "signal")), Galaxy.current_system if place.begins_with("point:") or place == "player" else ""]
			if h: h.call("markers_changed", id)
		"remove_marker":
			s["markers"].erase(str(a.get("marker", "")))
			if h: h.call("markers_changed", id)
		"drop_item":
			# (like spawns: dropped when you're in the place's system)
			s["drops"].append({"item": str(a.get("item", "")), "place": str(a.get("place", "player")), "system": "", "taken": false})
			if h and h.has_method("drop_pending"):
				h.call("drop_pending", id)
			elif h:
				h.call("drop_item", id, str(a.get("item", "")), str(a.get("place", "player")))
		"timer": s["timers"][str(a.get("timer", "timer"))] = float(a.get("seconds", 30))
		"set_var": s["vars"][str(a.get("var", ""))] = float(a.get("value", 0))
		"add_var": s["vars"][str(a.get("var", ""))] = float(s["vars"].get(str(a.get("var", "")), 0.0)) + float(a.get("value", 1))
		"lore": if h: h.call("unlock_lore", str(a.get("lore", "")))
		"start_scenario": start(str(a.get("scenario", "")))
		"finish", "fail":
			s["status"] = "finished" if action == "finish" else "failed"
			var steps: Array = find(id).get("steps", [])
			if action == "finish" and not steps.is_empty():
				s["step"] = steps[-1]
			s["objective"] = ""
			s["markers"] = {}
			var sc := find(id)
			_log(("Scenario complete: " if action == "finish" else "Scenario failed: ") + str(sc.get("title", id)))
			if h:
				h.call("markers_changed", id)
				h.call("objectives_changed")
				h.call("message", ("%s - complete!" if action == "finish" else "%s - failed") % sc.get("title", id))


## Dialogue lines: "Speaker: text" strings -> [speaker, text] pairs.
static func _lines(v: Variant) -> Array:
	var out := []
	for l in (v if v is Array else str(v).split("\n")):
		var t := str(l).strip_edges()
		if t == "":
			continue
		var i := t.find(":")
		out.append([t.substr(0, i).strip_edges(), t.substr(i + 1).strip_edges()] if i > 0 else ["", t])
	return out


## A ship of a scenario group was destroyed (the host reports it; `record`:
## which spawn it came from, -1 unknown).
static func group_ship_lost(id: String, group: String, record := -1) -> void:
	var s := _st(id)
	var spawns: Array = s.get("spawns", [])
	if record >= 0 and record < spawns.size():
		spawns[record]["left"] = maxi(0, int(spawns[record]["left"]) - 1)
	s["groups"][group] = maxi(0, int(s["groups"].get(group, 0)) - 1)
	if s["groups"][group] == 0:
		_fire(id, "group_gone", {"group": group})


## Objectives of active scenarios: [[title, text], ...].
static func objectives() -> Array:
	var out := []
	for id in state:
		var s: Dictionary = state[id]
		if s["status"] == "active" and s["objective"] != "":
			out.append([str(find(id).get("title", id)), s["objective"]])
	return out


static func _log(text: String) -> void:
	GameLog.post(text, "quest")


# --- Saving ------------------------------------------------------------------------

static func get_save_data() -> Dictionary:
	return state.duplicate(true)


static func load_save_data(d: Dictionary) -> void:
	state = d.duplicate(true)
	for id in state:
		var s: Dictionary = state[id]
		for k in ["vars", "timers", "markers", "groups", "every", "conds"]:
			if not s.has(k):
				s[k] = {}
		if not s.has("spawns"):
			s["spawns"] = []
		if not s.has("drops"):
			s["drops"] = []
		if not s.has("fired"):
			s["fired"] = []
	# Scenarios added to the game after this save was made (an empire's
	# story...): available in it too, from their beginning.
	for sc in all():
		if bool(sc.get("enabled", true)) and not state.has(sc["id"]):
			start(sc["id"])
