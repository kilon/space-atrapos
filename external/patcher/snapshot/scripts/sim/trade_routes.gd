class_name TradeRoutes
extends RefCounted
## Trade data for the market screen and the maps: commodity categories,
## galactic average prices, supply / demand levels and trade routes (buy a
## good at one station, sell it at another, the profit per unit).
##
## Everything reads one price table - every station's buy and sell price of
## every good - built at most once a second (prices move with the economy
## tick, every 2 s), so a map asking for routes every redraw costs nothing.
## A route search over the whole galaxy (~50 stations, 14 goods, every
## destination within reach) is a few thousand table lookups.

## Commodity groups, in the market's order: [title, [item ids]] - ten of
## fourteen goods each (TradeGoods; the original goods first in each).
const CATEGORIES := TradeGoods.CATEGORIES
## A station only sells a good it has at least this much of.
const MIN_STOCK := 5.0
## Routes worth showing: at least this many credits a unit.
const MIN_PROFIT := 3

static var _table := {}          # station id -> {item -> [buy, sell, stock]}


## The price table: Galaxy.price_cache (kept up as the stations tick; the
## galactic averages are kept with it - Galaxy.average_sell).
static func table() -> Dictionary:
	var t: Dictionary = Galaxy.price_cache
	for sid in Galaxy.stations:
		if not t.has(sid):
			Galaxy.cache_prices(sid)
	_table = t
	return t


## Forget the averages and cached routes (the prices just moved).
static func invalidate() -> void:
	_routes_at = -1000000
	_job = {}


static func category_of(item: String) -> String:
	for cat in CATEGORIES:
		if item in cat[1]:
			return cat[0]
	return "Other"


## The galactic average price of a good (what stations pay, on average).
static func average(item: String) -> int:
	var a := Galaxy.average_sell(item)
	return roundi(a if a > 0.0 else float(Items.ITEMS.get(item, {}).get("value", 0)))


## Supply at a station, 0..3 bars (0: none to sell).
static func supply_bars(sid: String, item: String) -> int:
	var stock: float = Galaxy.stations.get(sid, {}).get("stock", {}).get(item, 0.0)
	var k := 10.0 if item == "alien_alloy" else 100.0
	if stock < MIN_STOCK * k / 100.0:
		return 0
	if stock < k * 0.35:
		return 1
	return 2 if stock < k * 1.6 else 3


## Demand at a station, 0..3 bars: only goods the station uses (its economy
## consumes them), more bars the shorter of them it is.
static func demand_bars(sid: String, item: String) -> int:
	var st: Dictionary = Galaxy.stations.get(sid, {})
	if st.is_empty() or not Galaxy.uses(st["economy"], item):
		return 0
	var k := 10.0 if item == "alien_alloy" else 100.0
	var short := clampf(1.0 - float(st["stock"].get(item, 0.0)) / (k * 1.2), 0.0, 1.0)
	return 1 + roundi(short * 2.0)


## Can the player trade at this station? (Not where its owner considers you an
## enemy, nor at pirate dens.)
static func open_to_player(sid: String) -> bool:
	return not Galaxy.is_hostile_to_player(Galaxy.station_owner(sid))


## Jumps from `sys_id` to every system within `max_jumps` (BFS over the gate
## lanes): system id -> jumps.
static var _reach := {}   # "<system>|<jumps>" -> reach (the lanes never change)

static func reach(sys_id: String, max_jumps: int) -> Dictionary:
	var key := "%s|%d" % [sys_id, max_jumps]
	if _reach.has(key):
		return _reach[key]
	var out := {sys_id: 0}
	var frontier := [sys_id]
	for j in max_jumps:
		var next := []
		for s in frontier:
			for n in Galaxy.neighbors(s):
				if not out.has(n):
					out[n] = j + 1
					next.append(n)
		frontier = next
	_reach[key] = out
	return out


## Only what you know (Galaxy.knows_market / knows_station): a route starts
## at a station whose market you know (docked there, or its empire is
## Friendly with you) and ends at one you've found.
##
## The best routes starting at the stations `from_sids`: for each starting
## station and good, the destination (within `max_jumps`) paying the most for
## it (`other_systems`: only in other systems). `item` "" = every good. Sorted by profit per unit, best first.
## Each: {item, from, to, from_sys, to_sys, buy, sell, profit, jumps, stock}.
static func routes_from(from_sids: Array, max_jumps := 2, item := "", limit := 10, other_systems := false) -> Array:
	var t := table()
	var out := []
	var reaches := {}
	for a in from_sids:
		if not t.has(a):
			continue
		var asys: String = Galaxy.stations[a]["system"]
		if not open_to_player(a) or not Galaxy.knows_market(a):
			continue
		if not reaches.has(asys):
			reaches[asys] = reach(asys, max_jumps)
		var r: Dictionary = reaches[asys]
		for c in t[a]:
			if item != "" and c != item:
				continue
			var here: Array = t[a][c]
			if here[2] < (MIN_STOCK / 10.0 if c == "alien_alloy" else MIN_STOCK):
				continue
			var best := {}
			for bsys in r:
				if other_systems and bsys == asys:
					continue
				for b in Galaxy.system(bsys).get("stations", []):
					if b == a or not t.has(b) or not t[b].has(c) or not open_to_player(b) or not Galaxy.knows_station(b):
						continue
					var profit: int = t[b][c][1] - here[0]
					if profit >= MIN_PROFIT and (best.is_empty() or profit > best["profit"]):
						best = {"item": c, "from": a, "to": b, "from_sys": asys, "to_sys": bsys,
							"buy": here[0], "sell": t[b][c][1], "profit": profit, "jumps": r[bsys], "stock": int(here[2])}
			if not best.is_empty():
				out.append(best)
	out.sort_custom(func(x, y): return x["profit"] > y["profit"])
	return out.slice(0, limit)


## Every station in these systems.
static func stations_of(systems: Array) -> Array:
	var out := []
	for s in systems:
		out.append_array(Galaxy.system(s).get("stations", []))
	return out


## Where a good sells best within `max_jumps` of `sys_id` (excluding the
## station `except`): [{to, to_sys, sell, jumps}], best first.
static func best_sellers(item: String, sys_id: String, max_jumps := 2, except := "", limit := 4) -> Array:
	var t := table()
	var out := []
	var r := reach(sys_id, max_jumps)
	for s in r:
		for b in Galaxy.system(s).get("stations", []):
			if b != except and t.has(b) and t[b].has(item) and open_to_player(b) and Galaxy.knows_station(b):
				out.append({"to": b, "to_sys": s, "sell": t[b][item][1], "jumps": r[s]})
	out.sort_custom(func(x, y): return x["sell"] > y["sell"])
	return out.slice(0, limit)


## The best route between each pair of systems (from all of `systems`'
## stations, to any system within `max_jumps`), across systems only:
## [{route...}], best first, at most `limit` (one per system pair).
## For each system, the best price for each good it has to sell among the
## systems within reach (other than itself) first, then each station against
## that. With ~60 goods a station and every market known that's ~60 ms of
## work, so it's a job done in steps (_job_step): galaxy_routes() finishes it
## at once; galaxy_routes_spread() - the map, every frame - does ~1 ms a frame
## and shows the last finished routes meanwhile. Results are good for 2 s
## (the economy tick) per good and reach.
static var _routes_at := -1000000
static var _routes_key := ""
static var _routes: Array = []
static var _job := {}
const JOB_BUDGET_USEC := 1000


## The routes, worked out now (however long it takes).
static func galaxy_routes(item := "", max_jumps := 2, limit := 8) -> Array:
	var key := _routes_key_for(item, max_jumps, limit)
	if key == _routes_key and Time.get_ticks_msec() - _routes_at < 2000:
		return _routes
	if _job.is_empty() or _job["key"] != key:
		_job = _new_job(item, max_jumps, limit, key)
	while not _job.is_empty():
		_job_step(1000000000)
	return _routes


## The routes without a long frame: the search goes on a little each call
## (call it every frame); until it's done, the last finished routes for the
## same good and reach ([] if there are none yet).
static func galaxy_routes_spread(item := "", max_jumps := 2, limit := 8) -> Array:
	var key := _routes_key_for(item, max_jumps, limit)
	var stale := key != _routes_key or Time.get_ticks_msec() - _routes_at >= 2000
	if stale and (_job.is_empty() or _job["key"] != key):
		_job = _new_job(item, max_jumps, limit, key)
	if not _job.is_empty():
		_job_step(JOB_BUDGET_USEC)
	return _routes if _routes_key.get_slice("#", 0) == key.get_slice("#", 0) else []


static func _routes_key_for(item: String, max_jumps: int, limit: int) -> String:
	return "%s|%d|%d#%d" % [item, max_jumps, limit, Galaxy.knowledge]


static func _new_job(item: String, max_jumps: int, limit: int, key: String) -> Dictionary:
	var t: Dictionary = table().duplicate()   # (a snapshot: each station's row is replaced whole, never changed)
	return {"key": key, "item": item, "max_jumps": max_jumps, "limit": limit, "t": t, "stage": 0, "i": 0,
		"systems": Galaxy.SYSTEMS.keys(), "sids": t.keys(), "own": {}, "buyable": {}, "best_by": {}, "pairs": {}}


## Goes on with the search for `budget` microseconds (it may run a little
## over: one system or station at a time). Stages: each system's best seller
## per good; each system's goods worth buying; for each of those systems the
## best price in reach; each station against that; then the result.
static func _job_step(budget: int) -> void:
	var j := _job
	var t: Dictionary = j["t"]
	var item: String = j["item"]
	var until := Time.get_ticks_usec() + budget
	while Time.get_ticks_usec() < until:
		match int(j["stage"]):
			0:   # each system's own best seller per good
				if j["i"] >= j["systems"].size():
					j["stage"] = 1
					j["i"] = 0
					continue
				var y: String = j["systems"][j["i"]]
				j["i"] += 1
				var row := {}
				for b in Galaxy.system(y).get("stations", []):
					if not t.has(b) or not open_to_player(b) or not Galaxy.knows_station(b):
						continue
					var tb: Dictionary = t[b]
					for c in ([item] if item != "" else tb.keys()):
						if not tb.has(c):
							continue   # (a good this station doesn't deal in)
						var sell: int = tb[c][1]
						if not row.has(c) or sell > row[c][0]:
							row[c] = [sell, b]
				j["own"][y] = row
			1:   # the goods worth buying in each system (known, open stations' stock)
				if j["i"] >= j["sids"].size():
					j["stage"] = 2
					j["i"] = 0
					j["xs"] = j["buyable"].keys()
					continue
				var a: String = j["sids"][j["i"]]
				j["i"] += 1
				if not Galaxy.stations.has(a) or not open_to_player(a) or not Galaxy.knows_market(a):
					continue
				var set: Dictionary = j["buyable"].get_or_add(Galaxy.stations[a]["system"], {})
				var ta: Dictionary = t[a]
				for c in ta:
					if (item == "" or c == item) and ta[c][2] >= (MIN_STOCK / 10.0 if c == "alien_alloy" else MIN_STOCK):
						set[c] = true
			2:   # for each such system, the best price for its goods within reach
				if j["i"] >= j["xs"].size():
					j["stage"] = 3
					j["i"] = 0
					continue
				var x: String = j["xs"][j["i"]]
				j["i"] += 1
				var row := {}
				var r := reach(x, j["max_jumps"])
				var wanted: Array = j["buyable"][x].keys()
				for y in r:
					if y == x:
						continue
					var oy: Dictionary = j["own"].get(y, {})
					for c in wanted:
						if oy.has(c) and (not row.has(c) or oy[c][0] > row[c][0]):
							row[c] = [oy[c][0], oy[c][1], y, r[y]]
				j["best_by"][x] = row
			3:   # each station against the best price in reach: the best run per pair of systems
				if j["i"] >= j["sids"].size():
					j["stage"] = 4
					return   # (the sort and the result: a frame of their own)
				var a: String = j["sids"][j["i"]]
				j["i"] += 1
				if not Galaxy.stations.has(a):
					continue
				var asys: String = Galaxy.stations[a]["system"]
				var row: Dictionary = j["best_by"].get(asys, {})
				if row.is_empty() or not open_to_player(a) or not Galaxy.knows_market(a):
					continue
				var ta: Dictionary = t[a]
				for c in row:
					if not ta.has(c):
						continue
					var here: Array = ta[c]
					if here[2] < (MIN_STOCK / 10.0 if c == "alien_alloy" else MIN_STOCK):
						continue
					var profit: int = row[c][0] - here[0]
					if profit < MIN_PROFIT:
						continue
					var k: String = asys + ">" + row[c][2]
					if not j["pairs"].has(k) or profit > j["pairs"][k][0]:
						j["pairs"][k] = [profit, a, c, row[c]]
			4:
				_job_finish()
				return


static func _job_finish() -> void:
	var j := _job
	var t: Dictionary = j["t"]
	var pairs: Dictionary = j["pairs"]
	var keys: Array = pairs.keys()
	keys.sort_custom(func(x, y): return pairs[x][0] > pairs[y][0])
	var out := []
	for k in keys.slice(0, j["limit"]):
		var p: Array = pairs[k]
		var a: String = p[1]
		var c: String = p[2]
		var best: Array = p[3]
		out.append({"item": c, "from": a, "to": best[1], "from_sys": Galaxy.stations[a]["system"], "to_sys": best[2],
			"buy": t[a][c][0], "sell": best[0], "profit": p[0], "jumps": best[3], "stock": int(t[a][c][2])})
	_routes_key = j["key"]
	_routes_at = Time.get_ticks_msec()
	_routes = out
	_job = {}


static func station_name(sid: String) -> String:
	return Galaxy.stations.get(sid, {}).get("name", "?")


static func system_name(sys_id: String) -> String:
	return Galaxy.SYSTEMS.get(sys_id, {}).get("name", "?")


# --- Drawing (the maps) --------------------------------------------------------------

const RUN_COLOR := Color(0.45, 1.0, 0.55)


## A trade run along `pts` (screen points, start to end): a glowing line,
## chevrons streaming toward the end (`t`: seconds, animates them) and an
## arrowhead. `k` 0..1: how good the run is (brighter, thicker).
static func draw_run(ci: CanvasItem, pts: PackedVector2Array, k: float, t: float) -> void:
	if pts.size() < 2:
		return
	var col := RUN_COLOR.lerp(Color(1.0, 0.95, 0.4), clampf(k, 0.0, 1.0) * 0.5)
	var w := 1.5 + 2.5 * k
	ci.draw_polyline(pts, Color(col, 0.16), w * 4.0, true)
	ci.draw_polyline(pts, Color(col, 0.9), w, true)
	# Chevrons every 28 px, sliding along.
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var gap := 28.0
	var d := fposmod(t * 40.0, gap)
	while d < total - 14.0:
		var at := _along(pts, d)
		_chevron(ci, at[0], at[1], 5.0 + w, Color(col, 0.95))
		d += gap
	var end := pts[-1]
	var dir := (pts[-1] - pts[-2]).normalized()
	var s := 9.0 + w * 1.5
	ci.draw_colored_polygon(PackedVector2Array([end, end - dir * s + dir.orthogonal() * s * 0.6, end - dir * s - dir.orthogonal() * s * 0.6]), col)


static func _along(pts: PackedVector2Array, d: float) -> Array:
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if d <= l:
			var dir := (pts[i + 1] - pts[i]) / maxf(l, 0.001)
			return [pts[i] + dir * d, dir]
		d -= l
	return [pts[-1], (pts[-1] - pts[-2]).normalized()]


static func _chevron(ci: CanvasItem, at: Vector2, dir: Vector2, s: float, col: Color) -> void:
	var n := dir.orthogonal()
	ci.draw_polyline(PackedVector2Array([at - dir * s * 0.5 + n * s * 0.6, at + dir * s * 0.4, at - dir * s * 0.5 - n * s * 0.6]), col, 2.0, true)


## A small label box (a run's good and profit) centred on `at` - moved down
## (or up) out of the way of the boxes already in `taken` (it joins them).
static func draw_tag(ci: CanvasItem, at: Vector2, text: String, fs: int, taken: Array = []) -> void:
	var font := NeonTheme.heavy_font()
	var sz := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var r := Rect2(at - Vector2(sz.x / 2.0 + 6.0, fs * 0.5 + 3.0), Vector2(sz.x + 12.0, fs + 6.0))
	var start := r.position
	for i in 12:
		var hit := false
		for o in taken:
			if r.grow(2.0).intersects(o):
				hit = true
				break
		if not hit:
			break
		var k := (i / 2 + 1) * (1 if i % 2 == 0 else -1)
		r.position = start + Vector2(0, k * (fs + 9.0))
	taken.append(r)
	ci.draw_rect(r, Color(0.0, 0.05, 0.02, 0.85))
	ci.draw_rect(r, Color(RUN_COLOR, 0.7), false, 1.0)
	ci.draw_string(font, Vector2(r.position.x + 6.0, r.position.y + fs * 0.85 + 2.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, RUN_COLOR.lightened(0.3))


## "FOOD +23" - a run's tag.
static func tag_text(r: Dictionary) -> String:
	return "%s +%d" % [Items.display_name(r["item"]).to_upper(), r["profit"]]
