class_name RepairService
extends RefCounted
## A station's repair service: an EVALUATION first - the technicians go over
## the ship and the automaton and list everything damaged (the hull; each
## damaged part's affliction and the faults in it, traced or not) with what
## each costs to put right - then a REPAIR of what you choose (each on its own,
## a part's faults together, or everything), done by them over time: up to
## MAX_TIME s, longer the more there is (docked, you wait; undock and what's not
## done yet is refunded). It's dear: at least MARKUP times what the same repair
## costs done yourself (manual_cost: the spare part a wreck takes, the
## materials the rest use; the hull: a Repair Kit's worth).
##   var ev := RepairService.evaluate(data, ship)   # [item...]
##   var job := RepairService.start(data, items)    # then tick(job, delta) while docked

const MARKUP := 10.0
const MAX_TIME := 60.0
## What mending a fault yourself costs in materials (sealant, solder, welding rod...): by kind, x its severity.
const MATERIALS := {"crack": 14.0, "burn": 18.0, "leak": 12.0, "drift": 10.0}
## Hull by hand: a Repair Kit mends 40 for its price.
const KIT_HULL := 40.0


## The materials and parts a fault takes, mended in the Repair Bay.
static func manual_cost(which: String, pid: String, f: Dictionary) -> float:
	if str(f["kind"]) == "wreck":
		var kind: String = Parts.comps(which, pid)[int(f["comp"])][0]
		return float(Items.ITEMS[Parts.SPARE_OF[kind]]["price"])
	return float(MATERIALS.get(str(f["kind"]), 12.0)) * (0.5 + float(f.get("sev", 0.5)))


## The station's price for it (MARKUP times the manual cost, never less).
static func price_of(manual: float) -> int:
	return maxi(10, ceili(manual * MARKUP / 5.0) * 5)


## The technicians' time on a fault (s, before the whole job is fitted into MAX_TIME).
static func time_of(f: Dictionary) -> float:
	return 14.0 if str(f["kind"]) == "wreck" else 5.0 + 10.0 * float(f.get("sev", 0.5))


## Everything damaged, priced: [{key, body, part, kind ("hull"/"fault"), fault (its id),
## name, detail, price, time, manual}] - the hull first, then each part's faults
## under it (with its affliction: `part_name`, `affliction`). Traces the hidden faults.
static func evaluate(data: Node, ship: Node2D) -> Array:
	var out := []
	if ship != null:
		var missing := ceilf(float(ship.max_hull) - float(ship.hull))
		if missing >= 1.0:
			var manual := missing / KIT_HULL * float(Items.ITEMS["repair_kit"]["price"])
			out.append({"key": "hull", "body": "ship", "part": "", "kind": "hull", "fault": -1, "name": "Hull breaches",
				"detail": "%d of %d hull points" % [missing, roundi(float(ship.max_hull))], "manual": manual,
				"price": price_of(manual), "time": 1.0 + 20.0 * missing / maxf(1.0, float(ship.max_hull))})
	for which in ["ship", "automaton"]:
		var cond: Dictionary = data.condition
		if not cond.has(which):
			continue
		for a in Parts.afflictions(cond, which):
			if a["part"] == "":
				continue
			var pid: String = a["part"]
			for f in Parts.part(cond, which, pid)["faults"]:
				f["found"] = true   # (the technicians trace everything)
				var fi := Parts.fault_info(which, pid, f)
				var manual := manual_cost(which, pid, f)
				out.append({"key": "%s:%s:%d" % [which, pid, int(f["id"])], "body": which, "part": pid, "kind": "fault", "fault": int(f["id"]),
					"name": fi["name"], "detail": "%s - severity %d%%" % [Parts.comps(which, pid)[int(f["comp"])][1], roundi(float(f["sev"]) * 100.0)],
					"part_name": Parts.info(which, pid)["name"], "affliction": a["name"], "manual": manual,
					"price": price_of(manual), "time": time_of(f)})
	return out


static func total(items: Array) -> int:
	var n := 0
	for it in items:
		n += int(it["price"])
	return n


## The job's time: each item's, the whole fitted into MAX_TIME (at least 3 s).
static func job_time(items: Array) -> float:
	var t := 0.0
	for it in items:
		t += float(it["time"])
	return clampf(t, 3.0, MAX_TIME)


## A repair job begins: paid for, its items in order, each its share of the time.
## {} if it can't be paid.
static func start(data: Node, items: Array) -> Dictionary:
	if items.is_empty():
		return {}
	var cost := total(items)
	if not data.spend(cost):
		return {}
	var raw := 0.0
	for it in items:
		raw += float(it["time"])
	var k := job_time(items) / maxf(0.001, raw)
	var queue := []
	for it in items:
		var q: Dictionary = it.duplicate()
		q["time"] = float(it["time"]) * k
		queue.append(q)
	return {"items": queue, "t": 0.0, "done": 0, "paid": cost, "total": job_time(items)}


## Moves the job on by `delta` s: finishes the items whose time has come (the
## ship's hull, the parts' faults). Returns the items finished this time.
static func tick(job: Dictionary, delta: float, data: Node, ship: Node2D) -> Array:
	var out := []
	if job.is_empty():
		return out
	job["t"] = float(job["t"]) + delta
	var items: Array = job["items"]
	var at := 0.0
	for i in items.size():
		at += float(items[i]["time"])
		if i < int(job["done"]):
			continue
		if float(job["t"]) < at:
			break
		_finish(items[i], data, ship)
		job["done"] = i + 1
		out.append(items[i])
	return out


static func finished(job: Dictionary) -> bool:
	return not job.is_empty() and int(job["done"]) >= (job["items"] as Array).size()


## The share of the job done (0..1).
static func progress(job: Dictionary) -> float:
	return clampf(float(job.get("t", 0.0)) / maxf(0.001, float(job.get("total", 1.0))), 0.0, 1.0)


## What's not done yet is paid back (undocking mid-job). The refund.
static func cancel(job: Dictionary, data: Node) -> int:
	if job.is_empty():
		return 0
	var back := 0
	var items: Array = job["items"]
	for i in range(int(job["done"]), items.size()):
		back += int(items[i]["price"])
	if back > 0:
		data.add_credits(back)
	job["items"] = items.slice(0, int(job["done"]))
	return back


static func _finish(it: Dictionary, data: Node, ship: Node2D) -> void:
	match str(it["kind"]):
		"hull":
			if ship:
				ship.repair(float(ship.max_hull) - float(ship.hull))
		"fault":
			Parts.clear_fault(data.condition, it["body"], it["part"], int(it["fault"]))
	if ship and ship.has_method("apply_tech"):
		ship.apply_tech()
	data.changed.emit()
