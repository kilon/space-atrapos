class_name NavReports
extends RefCounted
## Navigation reports: scanning a system's navigation beacon (NavBeacon,
## Main.scan_beacon) makes a report of the system as it is - its stations,
## planets and moons, jump gates, the ships about (hostile, friendly and
## neutral, by empire and by trade), monsters, asteroids, wrecks and signals -
## shown at once (NavReportPanel) and put in your hold as an item,
## "navrep:<system id>". Stations in OTHER systems buy reports: the further
## (jumps between the systems) the more they pay; worthless in its own system.
## One report a visit: a beacon gives another only after you've left the system
## and come back (Galaxy.jumps). Reports are kept with the galaxy (Galaxy.reports).

const PREFIX := "navrep:"
## A report's price: BASE + PER_JUMP a jump away (+ PER_STATION for each of its
## system's stations: busier systems' charts sell better).
const BASE := 60
const PER_JUMP := 70
const PER_STATION := 10


static func id_for(sys_id: String) -> String:
	return PREFIX + sys_id


static func is_report(id: String) -> bool:
	return id.begins_with(PREFIX)


static func system_of(id: String) -> String:
	return id.substr(PREFIX.length()) if is_report(id) else ""


static func valid(id: String) -> bool:
	return is_report(id) and Galaxy.SYSTEMS.has(system_of(id))


## The item: kind "report" (sold at stations, never in "sell all cargo").
static func info(id: String) -> Dictionary:
	if not valid(id):
		return {}
	var sys := system_of(id)
	var r: Dictionary = Galaxy.reports.get(sys, {})
	var desc := "A navigation report of the %s system, made at its beacon. Stations in other systems buy it - the further from %s, the more they pay; worthless in its own system." % [name_of(sys), name_of(sys)]
	if not r.is_empty():
		desc += "\n%s" % summary(r)
	return {"name": "Nav Report: %s" % name_of(sys), "kind": "report", "value": 0, "desc": desc}


static func name_of(sys: String) -> String:
	return str(Galaxy.SYSTEMS.get(sys, {}).get("name", sys))


## Jumps between two systems (the shortest way along the lanes); -1 if none.
static func jumps(a: String, b: String) -> int:
	if a == b:
		return 0
	var seen := {a: 0}
	var q: Array = [a]
	while not q.is_empty():
		var s: String = q.pop_front()
		for n in Galaxy.neighbors(s):
			if not seen.has(n):
				seen[n] = seen[s] + 1
				if n == b:
					return seen[n]
				q.append(n)
	return -1


## What a station in system `at` pays for the report of system `sys` (0 there).
static func price(sys: String, at: String) -> int:
	var j := jumps(sys, at)
	if j <= 0:
		return 0
	var st: int = Galaxy.system(sys).get("stations", []).size() if Galaxy.systems.has(sys) else 0
	return BASE + PER_JUMP * j + PER_STATION * st


## The report of the system you're in, made from what's in it now (Main's scene).
static func make(tree: SceneTree, sys: String) -> Dictionary:
	var r := {"sys": sys, "name": name_of(sys), "owner": Galaxy.empire_name(Galaxy.owner_of(sys)),
		"stations": [], "bodies": [], "gates": [], "hostile": {}, "friendly": {}, "roles": {},
		"monsters": [], "rocks": 0, "wrecks": 0, "signals": 0, "made": Time.get_datetime_string_from_system(false, true)}
	for st in tree.get_nodes_in_group("stations"):
		r["stations"].append([str(st.get("station_name")), Galaxy.empire_name(str(st.get("empire")))])
	for b in tree.get_nodes_in_group("planet_bodies"):
		if str(b.get("title")) == "":
			continue
		var parent = b.get("parent_body")
		var spec = b.get("spec")
		r["bodies"].append([str(b.title), str(spec.get("name", "")) if spec is Dictionary else "", bool(b.get("landable")),
			str(parent.title) if parent != null and is_instance_valid(parent) else ""])
	for g in tree.get_nodes_in_group("gates"):
		r["gates"].append(str(g.get("target_name")) if str(g.get("target_name")) != "" else name_of(str(g.get("target"))))
	var main := tree.current_scene
	for holder in ["enemies", "neutrals"]:
		var box = main.get(holder) if main else null
		if box == null:
			continue
		for s in (box as Node).get_children():
			if s.has_method("is_alive") and not s.is_alive():
				continue
			if s.get("role") == null:
				continue
			if EnemyTypes.MONSTERS.has(str(s.type_id)):   # (a monster)
				r["monsters"].append(str(s.display_name) if str(s.display_name) != "" else str(EnemyTypes.MONSTERS[s.type_id].get("name", s.type_id)))
				continue
			var who: String = Galaxy.empire_name(str(s.empire)) if str(s.empire) != "" else ("Pirates" if str(s.role) == "pirate" else "Independent")
			var side: String = "hostile" if s.has_method("is_hostile_to_player") and s.is_hostile_to_player() else "friendly"
			r[side][who] = int(r[side].get(who, 0)) + 1
			var role: String = str(s.role) if str(s.role) != "" else "other"
			r["roles"][role] = int(r["roles"].get(role, 0)) + 1
	r["rocks"] = tree.get_nodes_in_group("asteroids").size()
	r["wrecks"] = tree.get_nodes_in_group("wrecks").filter(func(w): return not w.get("salvaged")).size()
	r["signals"] = tree.get_nodes_in_group("signal_beacons").size()
	return r


static func total(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


## "3 stations, 7 planets and moons, 2 gates; 4 hostile ships, 12 others; 40 asteroids".
static func summary(r: Dictionary) -> String:
	return "%d stations, %d planets and moons, %d gates; %d hostile ships, %d others%s; %d asteroids" % [
		r["stations"].size(), r["bodies"].size(), r["gates"].size(), total(r["hostile"]), total(r["friendly"]),
		(", %d monsters" % r["monsters"].size()) if not r["monsters"].is_empty() else "", int(r["rocks"])]


## The item's icon: a chart slate - an orbit, a star, a course across it.
static func draw_icon(ci: CanvasItem, _id: String, rect: Rect2, dim := false) -> void:
	var a := 0.35 if dim else 1.0
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) / 2.0
	var slate := Rect2(c - Vector2(s * 0.78, s * 0.9), Vector2(s * 1.56, s * 1.8))
	ci.draw_rect(slate, Color(0.08, 0.16, 0.22, 0.95 * a))
	ci.draw_rect(slate, Color(0.45, 1.0, 0.7, a), false, maxf(1.0, s * 0.08))
	ci.draw_arc(c + Vector2(0, s * 0.05), s * 0.5, 0, TAU, 24, Color(0.45, 1.0, 0.7, 0.7 * a), maxf(1.0, s * 0.06), true)
	ci.draw_circle(c + Vector2(0, s * 0.05), s * 0.16, Color(1.0, 0.82, 0.4, a))
	ci.draw_circle(c + Vector2(s * 0.5, s * 0.05), s * 0.09, Color(0.5, 0.75, 1.0, a))
	ci.draw_line(c + Vector2(-s * 0.6, s * 0.7), c + Vector2(s * 0.6, -s * 0.65), Color(1.0, 0.7, 0.3, 0.9 * a), maxf(1.0, s * 0.07), true)
