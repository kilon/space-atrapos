class_name Themes
## Named look presets for every customisable asset (buildings,
## planets, suns, nebulae, the GUI), saved in data/themes.json, each with
## rules saying where and when the game uses it:
##   enabled      false: never picked (kept for later)
##   systems      star systems it may appear in ([] = any)
##   owners       empires whose space (sector) it may appear in ([] = any)
##   planets      planets (surfaces) it may appear on ([] = any)
##   states       system conditions: boom, famine, civil_unrest... ([] = any)
##   templates    which of the asset's templates it applies to ([] = any)
##   friends      only while you're Friendly or better with one of these empires
##                ([] = any)
##   chapter_min / chapter_max   main-story chapters (stage numbers; -1 = no limit)
##   chance       0-1: how often it's used where it matches
##   priority     higher wins over lower when several match
## pick(kind, context, seed) returns the look to use (or {} for the default).

const FILE := "res://data/themes.json"
const KINDS := ["building", "planet", "star", "nebula", "asteroid", "gui"]
const RULE_DEFAULTS := {"enabled": true, "systems": [], "owners": [], "planets": [], "states": [], "templates": [],
	"friends": [], "chapter_min": -1, "chapter_max": -1, "chance": 1.0, "priority": 0}

static var _data := {}
static var _loaded := false
## The main story's current stage (the quest runner keeps it up to date).
static var chapter := -1


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	_data = DataFiles.read(FILE)
	if not _data.has("presets"):
		_data = {"presets": []}


static func reload() -> void:
	_loaded = false
	_load()


## Every preset of a kind: [{name, kind, look, rules}, ...].
static func presets(kind: String) -> Array:
	_load()
	return (_data["presets"] as Array).filter(func(p): return p.get("kind") == kind)


static func find(kind: String, name: String) -> Dictionary:
	for p in presets(kind):
		if p.get("name") == name:
			return p
	return {}


## Saves (or replaces) a named preset; returns the file written.
static func save_preset(kind: String, name: String, look: Dictionary, rules: Dictionary) -> String:
	_load()
	var list: Array = _data["presets"]
	for i in range(list.size() - 1, -1, -1):
		if list[i].get("kind") == kind and list[i].get("name") == name:
			list.remove_at(i)
	var r := RULE_DEFAULTS.duplicate(true)
	r.merge(rules, true)
	list.append({"name": name, "kind": kind, "look": encode(look), "rules": r})
	return DataFiles.write(FILE, _data)


static func delete_preset(kind: String, name: String) -> String:
	_load()
	_data["presets"] = (_data["presets"] as Array).filter(func(p): return not (p.get("kind") == kind and p.get("name") == name))
	return DataFiles.write(FILE, _data)


## A preset's look as values (colours and vectors decoded).
static func look_of(preset: Dictionary) -> Dictionary:
	return decode(preset.get("look", {}))


static func rules_of(preset: Dictionary) -> Dictionary:
	var r := RULE_DEFAULTS.duplicate(true)
	r.merge(preset.get("rules", {}), true)
	return r


## Where we are now: {system, owner, state, planet, friends (empires that like you), chapter}.
static func context(planet := "") -> Dictionary:
	var sys: String = Galaxy.current_system
	return {"system": sys, "owner": Galaxy.owner_of(sys), "state": Galaxy.state_of(sys), "planet": planet,
		"friends": Galaxy.MAJOR.filter(func(e): return Galaxy.standing(e) in ["Friendly", "Allied"]), "chapter": chapter}


## True if a preset's rules allow it in this context (template: the asset's).
static func matches(rules: Dictionary, ctx: Dictionary, template := "") -> bool:
	var r := RULE_DEFAULTS.duplicate(true)
	r.merge(rules, true)
	if not bool(r["enabled"]):
		return false
	for pair in [["systems", "system"], ["owners", "owner"], ["planets", "planet"], ["states", "state"]]:
		var allowed: Array = r[pair[0]]
		if not allowed.is_empty() and not allowed.has(ctx.get(pair[1], "")):
			return false
	var fr: Array = r["friends"]
	if not fr.is_empty() and not fr.any(func(e): return e in ctx.get("friends", [])):
		return false
	var tl: Array = r["templates"]
	if not tl.is_empty() and template != "" and not tl.has(template):
		return false
	var ch := int(ctx.get("chapter", -1))
	if int(r["chapter_min"]) >= 0 and ch < int(r["chapter_min"]):
		return false
	if int(r["chapter_max"]) >= 0 and ch > int(r["chapter_max"]):
		return false
	return true


## The look the game should use for an asset of `kind` here ({} = its own).
## Among matching presets the highest priority wins; `seed` makes the
## chance roll and ties stable (the same NPC keeps its look).
static func pick(kind: String, ctx: Dictionary, seed := 0, template := "") -> Dictionary:
	var best: Array = []
	var best_p := -INF
	for p in presets(kind):
		var r := rules_of(p)
		if not matches(r, ctx, template):
			continue
		var roll := float(absi(hash([p.get("name"), seed])) % 10000) / 10000.0
		if roll >= float(r["chance"]):
			continue
		var pr := float(r["priority"])
		if pr > best_p:
			best = [p]
			best_p = pr
		elif pr == best_p:
			best.append(p)
	if best.is_empty():
		return {}
	return look_of(best[absi(seed) % best.size()])


# --- JSON: colours and vectors as tagged arrays ----------------------------------

static func encode(look: Dictionary) -> Dictionary:
	var out := {}
	for k in look:
		var v = look[k]
		if v is Color:
			out[k] = ["color", v.r, v.g, v.b, v.a]
		elif v is Vector2:
			out[k] = ["vec2", v.x, v.y]
		elif v is Vector3:
			out[k] = ["vec3", v.x, v.y, v.z]
		elif v is Array or v is Dictionary:
			continue   # (tags and the like)
		else:
			out[k] = v
	return out


static func decode(look: Dictionary) -> Dictionary:
	var out := {}
	for k in look:
		var v = look[k]
		if v is Array and v.size() > 0 and v[0] is String:
			match v[0]:
				"color": out[k] = Color(v[1], v[2], v[3], v[4])
				"vec2": out[k] = Vector2(v[1], v[2])
				"vec3": out[k] = Vector3(v[1], v[2], v[3])
		else:
			out[k] = v
	return out
