class_name ProbeScanner
extends Node
## The probe scanner (equipment "probe_scanner", bought at an outfitter): scan
## probes launched across the system from the system map (MapPage's PROBES
## panel). Each probe reads what lies within its reach (`r`); an ANALYSIS
## (ANALYZE_TIME s) turns every signature in reach into a signal STRENGTH:
## each probe that covers it adds more the nearer it is to the middle of its
## reach and the tighter that reach is (REF_R / r), less for a faint kind of
## signature (KINDS' difficulty: a planet is plain, an anomaly faint), more with
## the sensors' probe strength (Upgrades). So a wide sweep finds that there's
## something; probes drawn tight round it pin it down:
##   below 25%  - an unknown signature, somewhere in a wide circle
##   25 - 75%   - its kind (anomaly / ship / body / structure), a smaller circle
##   75 - 100%  - what it is, a small circle
##   100%       - located: its name and exact place; an anomaly's beacon
##                appears (Galaxy signals "located"), a ship is tracked, the
##                place is charted - and you can set a course to it.
## The probes and the results are this system's (cleared on a jump).

const MAX_PROBES := 5
const RADII := [1000.0, 2000.0, 4000.0, 8000.0, 16000.0, 32000.0]
const REF_R := 2000.0
const PER_PROBE := 0.36
const ANALYZE_TIME := 3.5
const PROBE_SPEED := 9000.0
## Signature kinds: [name, how faint (x: harder), map colour].
const KINDS := {
	"anomaly": ["Anomaly", 1.0, Color(0.75, 0.5, 1.0)],
	"hostile": ["Hostile ship", 0.55, Color(1.0, 0.35, 0.3)],
	"neutral": ["Ship", 0.55, Color(0.5, 1.0, 0.75)],
	"body": ["Celestial body", 0.12, Color(0.6, 0.8, 1.0)],
	"structure": ["Structure", 0.2, Color(0.3, 0.9, 1.0)],
}

var main: Node
var ship: Node2D
var probes: Array = []       # [{pos, r, at (where it is now, flying out)}]
var results: Array = []      # [{id, kind, name, strength, pos (true), est (estimated), unc (uncertainty radius), node}]
var analyzing := -1.0        # s into an analysis (-1: none)
signal changed


func fitted() -> bool:
	var d: Node = main.player_data if main else null
	return d != null and d.has_equipment("probe_scanner")


## The sensors' probe strength (Upgrades) as a factor.
func strength_k() -> float:
	var d: Node = main.player_data if main else null
	return 1.0 + (d.mod("probe_strength") if d else 0.0)


## Launches probes to `spots` (each with the reach `r`): from the ship, they fly out.
func launch(spots: Array, r: float) -> void:
	for p in spots:
		if probes.size() >= MAX_PROBES:
			break
		probes.append({"pos": p, "r": r, "at": ship.global_position if ship else p})
	Sfx.play("space/missile", -8.0)
	changed.emit()


## Probes in a ring round `c` (`r` apart): MAX_PROBES of them, one in the middle.
func launch_pattern(c: Vector2, r: float) -> void:
	recall()
	var spots := [c]
	for i in MAX_PROBES - 1:
		spots.append(c + Vector2.from_angle(TAU * i / (MAX_PROBES - 1) - PI * 0.5) * r * 0.75)
	launch(spots, r)


func recall() -> void:
	probes = []
	analyzing = -1.0
	changed.emit()


## Every probe's reach a step up or down.
func step_all(d: int) -> void:
	for p in probes:
		p["r"] = step(float(p["r"]), d)
	changed.emit()


static func step(r: float, d: int) -> float:
	var i := RADII.find(r)
	if i < 0:
		i = 2
	return RADII[clampi(i + d, 0, RADII.size() - 1)]


func ready_to_analyze() -> bool:
	return not probes.is_empty() and analyzing < 0.0 and probes.all(func(p): return (p["at"] as Vector2).distance_to(p["pos"]) < 1.0)


func analyze() -> void:
	if probes.is_empty() or analyzing >= 0.0:
		return
	analyzing = 0.0
	Sfx.play("space/scan_pulse", -4.0, 0.02)
	changed.emit()


func _process(delta: float) -> void:
	var moving := false
	for p in probes:
		var at: Vector2 = p["at"]
		if at.distance_to(p["pos"]) > 1.0:
			p["at"] = at.move_toward(p["pos"], PROBE_SPEED * delta)
			moving = true
	if analyzing >= 0.0 and not moving:
		analyzing += delta
		if analyzing >= ANALYZE_TIME:
			analyzing = -1.0
			_resolve()
			changed.emit()
	elif moving:
		changed.emit()


## What there is to find in this system: [{id, kind, name, pos, node}].
func signatures() -> Array:
	var out := []
	var tree := get_tree()
	if main and main.get("site") == null:
		for sg in Galaxy.signals_in():
			if not sg["done"]:
				out.append({"id": "sig:%s" % sg["id"], "kind": "anomaly", "name": SignalSites.title(sg), "pos": SignalSites.pos(sg), "sig": sg})
	for e in tree.get_nodes_in_group("enemies") + tree.get_nodes_in_group("neutrals"):
		if not e.is_alive() or e.get("untouchable") == true:
			continue
		var hostile: bool = not e.is_neutral() or e.is_hostile_to_player()
		out.append({"id": "ship:%d" % e.get_instance_id(), "kind": "hostile" if hostile else "neutral", "name": e.display_name, "pos": e.global_position, "node": e})
	for b in tree.get_nodes_in_group("planet_bodies"):
		out.append({"id": "body:%s" % b.planet_id, "kind": "body", "name": b.title, "pos": b.global_position, "node": b})
	var star := tree.get_first_node_in_group("star")
	if star:
		out.append({"id": "star", "kind": "body", "name": star.star_name + " (star)", "pos": star.global_position, "node": star})
	for st in tree.get_nodes_in_group("stations"):
		out.append({"id": "station:%s" % st.station_id, "kind": "structure", "name": st.station_name, "pos": st.global_position, "node": st})
	for g in tree.get_nodes_in_group("gates"):
		out.append({"id": "gate:%s" % g.target, "kind": "structure", "name": "Gate to " + g.target_name, "pos": g.global_position, "node": g})
	for nb in tree.get_nodes_in_group("nav_beacons"):
		out.append({"id": "nav", "kind": "structure", "name": "Navigation beacon", "pos": nb.global_position, "node": nb})
	return out


## A signature's strength from the probes now (0..1).
func strength_of(pos: Vector2, kind: String) -> float:
	var total := 0.0
	var faint: float = KINDS[kind][1]
	for p in probes:
		var r: float = p["r"]
		var d := (p["pos"] as Vector2).distance_to(pos)
		if d > r:
			continue
		total += PER_PROBE * (1.0 - pow(d / r, 2.0)) * sqrt(REF_R / r) / faint
	return clampf(total * strength_k(), 0.0, 1.0)


## The analysis done: every signature in reach, its strength; what's pinned down is located.
func _resolve() -> void:
	var old := {}
	for r in results:
		old[r["id"]] = r
	results = []
	var located := 0
	for s in signatures():
		var st := strength_of(s["pos"], s["kind"])
		if st <= 0.01:
			continue
		# (an estimate: off by more the fainter, the same each analysis for the same probes)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(s["id"]) + str(probes.size()) + str(roundi(st * 20.0)))
		var avg_r := 0.0
		for p in probes:
			avg_r += float(p["r"])
		avg_r /= maxf(1.0, probes.size())
		var unc := (1.0 - st) * avg_r * 0.8
		var est: Vector2 = s["pos"] + Vector2.from_angle(rng.randf() * TAU) * unc * rng.randf_range(0.2, 0.8)
		var r := {"id": s["id"], "kind": s["kind"], "name": s["name"], "strength": st, "pos": s["pos"], "est": est, "unc": unc, "node": s.get("node")}
		if s.has("sig"):
			r["sig"] = s["sig"]
		results.append(r)
		if st >= 1.0:
			if not (old.has(s["id"]) and float(old[s["id"]]["strength"]) >= 1.0):
				located += 1
			_located(r)
	results.sort_custom(func(a, b): return float(a["strength"]) > float(b["strength"]))
	Sfx.play("space/scan_done", -4.0)
	GameLog.post("Probe analysis: %d signature%s%s." % [results.size(), "" if results.size() == 1 else "s",
		(", %d located" % located) if located > 0 else ""], "info")


func _located(r: Dictionary) -> void:
	if r.has("sig") and not r["sig"]["located"]:
		r["sig"]["located"] = true
		if main and main.has_method("refresh_beacons"):
			main.refresh_beacons()
		GameLog.post("Located: %s - its beacon is on your map. Fly there and ENTER." % r["name"], "mission")
		Sfx.play("space/signal_found", -3.0)
	Galaxy.reveal(r["pos"], 900.0)   # (charted round it on the map)


## How a result reads at its strength.
static func label(r: Dictionary) -> String:
	var st := float(r["strength"])
	if st >= 1.0:
		return r["name"]
	if st >= 0.75:
		return "%s?" % r["name"]
	if st >= 0.25:
		return KINDS[r["kind"]][0]
	return "Unknown signature"


## Results of a kind, for the map's icons: a located one shows exactly, the others as their circle.
func located(id: String) -> bool:
	for r in results:
		if r["id"] == id:
			return float(r["strength"]) >= 1.0
	return false
