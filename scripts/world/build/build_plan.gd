class_name BuildPlan
extends RefCounted
## A structure's pieces (BuildKit records, in its frame) and how they hold
## together - the rules of building, no visuals:
##
## Sockets: every plate's edges and corners at its top, every edge piece's
## top, every pillar's top - a new piece snaps to the socket nearest where
## you aim (snap): a foundation beside a foundation, a wall on a floor's or a
## foundation's edge or on the wall under it, a ceiling on the walls' tops
## (or beside another ceiling), a pillar on a corner, stairs in a square cell,
## a triangle against any edge - its other edges at 30 degree turns, the
## layouts angled. One piece a socket (an edge, a corner, a cell); plates
## never overlap (their outlines, any turn).
##
## Support (spans): foundations stand on the ground and hold up their tier's
## span; a wall, a pillar, a beam, stairs carry what they stand on's span up
## (never more than their own tier's); a ceiling or roof over walls / pillars
## / beams takes theirs, and reaches out from them a cell at a time, one less
## each cell (spans: timber 2, stone and marble 3, bronze 4 - past the cell
## over a wall, timber 1 cell, stone 2, bronze 3). A piece with
## nothing (span 0) holds up nothing and can't be placed; take a piece away
## and whatever only it held comes down with it (falling()).

var pieces: Array = []          # [record] (BuildKit)
var spans := PackedInt32Array()
## The ground's height in the frame under (x, z) - the foundations' fit (null: level at -0.4).
var ground := Callable()

var _plate := {}                # key(anchor) -> plate index
var _plates_y := {}             # quarter metres of height -> [plate index]
var _edge := {}                 # key(middle) -> edge piece index (ladders apart)
var _ladder := {}
var _corner := {}               # key(corner) -> pillar index
var _cell := {}                 # key(middle) -> stairs index
var _pedge := {}                # key(an edge's middle, at its plate's top) -> [plate index]
var _pcorner := {}              # key(a corner, at its plate's top) -> [plate index]
var last_snap := ""             # (snapping: the socket last shown, and its turn - kept against flicker)
var last_r := -1
var _free: Array = []           # [furniture index]
var _pe_y := {}                 # quarter metres of height -> [[a, b, plate index]] (its edges: overlapping ones hold each other)
var _we_y := {}                 # quarter metres of height (their feet) -> [[a, b, edge piece index]]
var _spans_on := true           # (a town's buildings: no spans wanted - only the lookups)


func _init(list: Array = [], with_spans := true) -> void:
	pieces = list
	_spans_on = with_spans
	reindex()


static func _yk(y: float) -> int:
	return roundi(y * 4.0)


## The lookups again (after any change) and the spans.
func reindex() -> void:
	_plate = {}
	_plates_y = {}
	_edge = {}
	_ladder = {}
	_corner = {}
	_cell = {}
	_pedge = {}
	_pcorner = {}
	_free = []
	_pe_y = {}
	_we_y = {}
	for i in pieces.size():
		var pc: Dictionary = pieces[i]
		var I := BuildKit.info(str(pc["t"]))
		var p := BuildKit.vec(pc["p"])
		match str(I.get("kind", "")):
			"plate":
				_plate[BuildKit.key(p)] = i
				var yk := _yk(p.y)
				if not _plates_y.has(yk):
					_plates_y[yk] = []
				_plates_y[yk].append(i)
				for e in BuildKit.edges(pc):
					_push(_pedge, BuildKit.key(e[2]), i)
					_push_k(_pe_y, yk, [e[0], e[1], i])
				for c in BuildKit.corners(pc):
					_push(_pcorner, BuildKit.key(c), i)
			"edge":
				if I.get("ladder", false) or I.get("outside", false):
					_ladder[_ladder_key(pc)] = i
				else:
					_edge[BuildKit.key(p)] = i
					var en := BuildKit.ends(pc)
					_push_k(_we_y, _yk(p.y), [en[0], en[1], i])
			"corner":
				_corner[BuildKit.key(p)] = i
			"cell":
				_cell[BuildKit.key(p)] = i
			"free":
				_free.append(i)
	if _spans_on:
		compute_spans()


static func _push(d: Dictionary, k: String, i: int) -> void:
	if not d.has(k):
		d[k] = []
	d[k].append(i)


static func _push_k(d: Dictionary, k: int, v) -> void:
	if not d.has(k):
		d[k] = []
	d[k].append(v)


## How much of two edges (along the ground) lie on each other, m: 0 unless they're on one line.
static func overlap_len(a1: Vector3, b1: Vector3, a2: Vector3, b2: Vector3) -> float:
	var A := Vector2(a1.x, a1.z)
	var d := Vector2(b1.x, b1.z) - A
	var L := d.length()
	if L < 0.01:
		return 0.0
	d /= L
	var n := Vector2(-d.y, d.x)
	var p2 := Vector2(a2.x, a2.z) - A
	var q2 := Vector2(b2.x, b2.z) - A
	if absf(p2.dot(n)) > 0.06 or absf(q2.dot(n)) > 0.06:
		return 0.0
	var t0 := minf(p2.dot(d), q2.dot(d))
	var t1 := maxf(p2.dot(d), q2.dot(d))
	return maxf(0.0, minf(L, t1) - maxf(0.0, t0))


## The plates whose edges lie along a..b at height y: [[index, overlap]].
func _plates_along(a: Vector3, b: Vector3, y: float, me := -1) -> Array:
	var out := []
	for e in _pe_y.get(_yk(y), []):
		if int(e[2]) != me:
			var o := overlap_len(a, b, e[0], e[1])
			if o > 0.4:
				out.append([int(e[2]), o])
	return out


static func _ladder_key(pc: Dictionary) -> String:
	return BuildKit.key(BuildKit.vec(pc["p"])) + "|%s|%d" % [str(pc["t"]), posmod(int(pc.get("r", 0)), 12)]


func _is(i: int, flag: String) -> bool:
	return i >= 0 and i < pieces.size() and bool(BuildKit.info(str(pieces[i]["t"])).get(flag, false))


func _sp(i: int, skip: int) -> int:
	return 0 if i == skip or i < 0 or i >= spans.size() else spans[i]


# --- Support -------------------------------------------------------------------------

## How far piece `pc` reaches (its span) from what holds it now: 0 nothing
## holds it. `me`: its own index (-1: not placed yet); `skip`: a piece taken away.
func support(pc: Dictionary, me := -1, skip := -1) -> int:
	if BuildKit.free_build:
		return 9   # (free building: everything holds)
	var id := str(pc["t"])
	var I := BuildKit.info(id)
	var cap := 9 if I["kind"] == "free" else BuildKit.span_of(int(pc.get("m", 1)))
	if I.get("found", false):
		return cap
	var p := BuildKit.vec(pc["p"])
	var best := 0
	var up := Vector3(0, BuildKit.WALL_H, 0)
	match str(I["kind"]):
		"plate":
			for e in BuildKit.edges(pc):
				for w in _we_y.get(_yk(p.y - BuildKit.WALL_H), []):   # (walls, beams under its edge)
					var wi: int = w[2]
					if wi != me and _is(wi, "bear") and overlap_len(e[0], e[1], w[0], w[1]) > 0.4:
						best = maxi(best, mini(cap, _sp(wi, skip)))
				for q in _plates_along(e[0], e[1], p.y, me):   # (a plate beside it: a cell further out)
					best = maxi(best, mini(cap, _sp(q[0], skip) - 1))
			for c in BuildKit.corners(pc):
				var q: int = _corner.get(BuildKit.key(c - up), -1)
				if q != me:
					best = maxi(best, mini(cap, _sp(q, skip)))
		"edge":
			var k := BuildKit.key(p)
			if I.get("hang", false):
				var eh := BuildKit.ends(pc)
				for q in _plates_along(eh[0], eh[1], p.y + BuildKit.WALL_H, me):
					if not _is(q[0], "roof"):
						best = maxi(best, mini(cap, _sp(q[0], skip)))
			var en := BuildKit.ends(pc)
			for q in _plates_along(en[0], en[1], p.y, me):   # (a floor or foundation under its foot)
				var j: int = q[0]
				if not _is(j, "roof") and float(q[1]) > 1.5:
					if id == "steps" and not _is(j, "found"):
						continue
					best = maxi(best, mini(cap, _sp(j, skip)))
			var w: int = _edge.get(BuildKit.key(p - up), -1)
			if w != me and _is(w, "bear"):
				best = maxi(best, mini(cap, _sp(w, skip)))
			if I.get("ladder", false):
				var w2: int = _edge.get(k, -1)
				if _is(w2, "bear") or _is(w2, "post"):
					best = maxi(best, mini(cap, _sp(w2, skip)))
			if I.get("beam", false):
				var vals := []
				for e in BuildKit.ends(pc):
					var q: int = _corner.get(BuildKit.key(e), -1)
					if q >= 0 and q != me:
						vals.append(_sp(q, skip))
				if vals.size() == 2:
					best = maxi(best, mini(cap, maxi(vals[0], vals[1])))
				elif vals.size() == 1:
					best = maxi(best, mini(cap, int(vals[0]) - 1))
		"corner":
			for j in _pcorner.get(BuildKit.key(p), []):
				if j != me and not _is(j, "roof"):
					best = maxi(best, mini(cap, _sp(j, skip)))
			var q: int = _corner.get(BuildKit.key(p - up), -1)
			if q != me:
				best = maxi(best, mini(cap, _sp(q, skip)))
		"cell":
			var j: int = _plate.get(BuildKit.key(p), -1)
			if j != me and j >= 0 and not _is(j, "roof"):
				best = maxi(best, mini(cap, _sp(j, skip)))
		"free":
			if I.get("wallfix", false):
				var w := wall_near(p, 0.5, me)
				if w >= 0:
					best = maxi(best, _sp(w, skip))
			else:
				var j := plate_under(p, me)
				if j >= 0:
					best = maxi(best, _sp(j, skip))
				elif _ground_at(p.x, p.z) > p.y - 0.6:
					best = cap   # (on the ground itself)
	return clampi(best, 0, cap)


## Every piece's span, from the ground up (`skip`: as if that one were gone).
func compute_spans(skip := -1) -> void:
	var n := pieces.size()
	spans = PackedInt32Array()
	spans.resize(n)
	var order := range(n)
	order.sort_custom(func(a, b): return BuildKit.vec(pieces[a]["p"]).y < BuildKit.vec(pieces[b]["p"]).y)
	for pass_i in 64:
		var changed := false
		for i in order:
			var v := 0 if i == skip else support(pieces[i], i, skip)
			if v != spans[i]:
				spans[i] = v
				changed = true
		if not changed:
			break


## What would come down with piece `i` (its index too): the pieces left with nothing holding them.
func falling(i: int) -> Array:
	compute_spans(i)
	var out := [i]
	for j in pieces.size():
		if j != i and spans[j] <= 0:
			out.append(j)
	compute_spans()
	return out


# --- Lookups -------------------------------------------------------------------------

func plate_under(p: Vector3, me := -1) -> int:
	for j in _plates_y.get(_yk(p.y), []):
		if j != me and not _is(j, "roof") and _inside(BuildKit.corners(pieces[j]), p):
			return j
	return -1


## The wall (an edge piece that stands, not a fence) within `d` of `p` along the ground at its level.
func wall_near(p: Vector3, d: float, me := -1) -> int:
	var best := -1
	var bd := d
	for k in _edge:
		var j: int = _edge[k]
		if j == me or not _is(j, "post") or _is(j, "low"):
			continue
		var q := BuildKit.vec(pieces[j]["p"])
		if absf(q.y - p.y) > 0.1:
			continue
		var e := BuildKit.ends(pieces[j])
		var dd := _seg_dist(Vector2(p.x, p.z), Vector2(e[0].x, e[0].z), Vector2(e[1].x, e[1].z))
		if dd < bd:
			bd = dd
			best = j
	return best


static func _seg_dist(q: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return (a + ab * t).distance_to(q)


static func _inside(cs: Array, p: Vector3) -> bool:
	var pos := false
	var neg := false
	for i in cs.size():
		var a: Vector3 = cs[i]
		var b: Vector3 = cs[(i + 1) % cs.size()]
		var cr := (b.x - a.x) * (p.z - a.z) - (b.z - a.z) * (p.x - a.x)
		if cr > 1e-6:
			pos = true
		elif cr < -1e-6:
			neg = true
	return not (pos and neg)


func _ground_at(x: float, z: float) -> float:
	return float(ground.call(x, z)) if ground.is_valid() else -0.4


func index_at(k: String, kind: String) -> int:
	match kind:
		"plate": return _plate.get(k, -1)
		"edge": return _edge.get(k, -1)
		"corner": return _corner.get(k, -1)
		"cell": return _cell.get(k, -1)
	return -1


# --- Snapping ------------------------------------------------------------------------

## Where piece `id` would go aiming at `aim` (the frame's): the nearest socket
## of the kind it takes, within `near` m - {t, p, r} (r turned `turned` times:
## a quarter for squares and cells, half for walls, 30 degrees for furniture),
## or {} (nothing to snap to). An empty plan: a foundation at the middle.
##
## `ray_o`, `ray_d` (the camera's line of sight, structure-local): sockets judged by
## how near that line they are (it moves smoothly with the mouse - where it
## first meets something jumps metres over an edge), the taken ones passed over,
## the last one picked kept unless another is clearly nearer (no flicker
## between two alike).
func snap(id: String, aim: Vector3, turned := 0, near := 3.6, ray_o := Vector3.INF, ray_d := Vector3.ZERO) -> Dictionary:
	var I := BuildKit.info(id)
	if I.is_empty():
		return {}
	var best := {}
	var bd := near
	var up := Vector3(0, BuildKit.WALL_H, 0)
	var cands: Array = []   # [p, r, the point it's judged by]
	var idxs := []          # (the pieces near enough to offer a socket)
	for j in pieces.size():
		if BuildKit.vec(pieces[j]["p"]).distance_to(aim) < near + 7.0:
			idxs.append(j)
	match str(I["kind"]):
		"plate":
			var sh := str(I["shape"])
			var tri := sh == "tri"
			var inset := BuildKit.TRI_R if tri else BuildKit.CELL * 0.5
			var lift := Vector3(0, BuildKit.RISE * 0.5, 0) if I.get("roof", false) else Vector3.ZERO
			if pieces.is_empty() and I.get("found", false):
				return {"t": id, "p": [0.0, 0.0, 0.0], "r": 0}
			for j in idxs:
				var pj: Dictionary = pieces[j]
				var J := BuildKit.info(str(pj["t"]))
				if J["kind"] == "plate":
					if I.get("found", false) != J.get("found", false):
						continue
					for e in BuildKit.edges(pj):
						cands.append_array(attach(sh, e[0], e[1], e[3], turned, lift))
				elif J["kind"] == "edge" and (J.get("bear", false) or J.get("post", false)) and not J.get("low", false) and not I.get("found", false):
					var en := BuildKit.ends(pj)
					var n := BuildKit.turn(int(pj.get("r", 0))) * Vector3(0, 0, 1)
					for sd: float in [1.0, -1.0]:
						cands.append_array(attach(sh, en[0] + up, en[1] + up, n * sd, turned, lift))
				elif J["kind"] == "corner" and not I.get("found", false) and sh in ["sq", "quarter"]:
					inset = BuildKit.extent(sh).x
					var top := BuildKit.vec(pj["p"]) + up
					var b := BuildKit.turn(int(pj.get("r", 0)))
					for k in 4:   # (a square on a pillar: the four cells round its top)
						var d := b * Vector3((1 if k % 2 else -1) * inset, 0, (1 if k < 2 else -1) * inset)
						cands.append([top + d, int(pj.get("r", 0)), top + d + lift])
			if I.get("found", false) and not tri:   # (a foundation off on its own, on the frame's grid - halves and quarters on its half cells)
				var ex := BuildKit.extent(sh)
				var g := Vector3(floorf(aim.x / (ex.x * 2.0)) * ex.x * 2.0 + ex.x, 0.0, floorf(aim.z / (ex.y * 2.0)) * ex.y * 2.0 + ex.y)
				cands.append([g, 0, g + Vector3(0, 0.3, 0)])
			var step := 3 if sh in ["sq", "quarter"] else 0
			for c in cands:
				c[1] = posmod(int(c[1]) + step * turned, 12)
		"edge":
			var hang: bool = I.get("hang", false)
			var mid_h := minf(BuildKit.height(id), BuildKit.H) * 0.5
			for j in idxs:
				var pj: Dictionary = pieces[j]
				var J := BuildKit.info(str(pj["t"]))
				if J["kind"] == "plate" and not J.get("roof", false):
					if id == "steps" and not J.get("found", false):
						continue
					for e in BuildKit.edges(pj):
						if (e[0] as Vector3).distance_to(e[1]) < BuildKit.CELL - 0.1:
							continue   # (a wall takes a whole cell's edge)
						var at: Vector3 = (e[2] as Vector3) - (up if hang else Vector3.ZERO)
						if id == "steps" and _pedge.get(BuildKit.key(e[2]), []).size() > 1:
							continue   # (steps only on an outer edge)
						var n: Vector3 = e[3]
						if id == "ladder" and (aim - at).dot(n) < 0.0:
							n = -n
						cands.append([at, BuildKit.r_facing(n), at + Vector3(0, mid_h if not hang else BuildKit.H - 0.5, 0)])
				elif J["kind"] == "edge" and (J.get("bear", false) or J.get("post", false) or J.get("gable", false)) and id != "steps":
					var base := BuildKit.vec(pj["p"])
					var r0 := int(pj.get("r", 0))
					if id == "ladder":   # (against the wall, on the side you're looking from)
						var n := BuildKit.turn(r0) * Vector3(0, 0, 1)
						if (aim - base).dot(n) < 0.0:
							n = -n
						cands.append([base, BuildKit.r_facing(n), base + Vector3(0, 1.6, 0) + n * 0.3])
					elif not J.get("low", false) and not J.get("gable", false):
						cands.append([base + up, r0, base + up + Vector3(0, mid_h, 0)])
				elif J["kind"] == "corner" and I.get("beam", false):
					var base := BuildKit.vec(pj["p"])
					for k in 12:
						var d := BuildKit.turn(k) * Vector3(BuildKit.CELL * 0.5, 0, 0)
						cands.append([base + d, k, base + d + Vector3(0, BuildKit.H - 0.3, 0)])
			for c in cands:
				c[1] = posmod(int(c[1]) + 6 * turned, 12)
		"corner":
			for j in idxs:
				var pj: Dictionary = pieces[j]
				var J := BuildKit.info(str(pj["t"]))
				if J["kind"] == "plate" and not J.get("roof", false):
					for c in BuildKit.corners(pj):
						cands.append([c, int(pj.get("r", 0)), c + Vector3(0, 1.5, 0)])
				elif J["kind"] == "corner":
					var top := BuildKit.vec(pj["p"]) + up
					cands.append([top, int(pj.get("r", 0)), top + Vector3(0, 1.5, 0)])
		"cell":
			for j in idxs:
				var pj: Dictionary = pieces[j]
				var J := BuildKit.info(str(pj["t"]))
				if J["kind"] == "plate" and not J.get("roof", false) and str(J["shape"]) == "sq":
					var at := BuildKit.vec(pj["p"])
					cands.append([at, posmod(int(pj.get("r", 0)) + 3 * turned, 12), at + Vector3(0, 1.0, 0)])
		"free":
			return snap_free(id, aim, turned)
	var by_ray := ray_o != Vector3.INF
	var kind := str(I["kind"])
	for c in cands:
		var q: Vector3 = c[2]
		var d := q.distance_to(aim)
		if by_ray:
			if d > near * 1.6:
				continue
			var t := maxf(0.0, (q - ray_o).dot(ray_d))
			d = q.distance_to(ray_o + ray_d * t) + d * 0.15
			if _taken(kind, I, c[0]):
				continue
			if BuildKit.key(c[0]) == last_snap and int(c[1]) == last_r:
				d -= 0.5   # (the one already shown: kept unless another's clearly nearer)
		if d < bd:
			bd = d
			best = {"t": id, "p": BuildKit.arr(c[0]), "r": int(c[1])}
	if by_ray:
		last_snap = BuildKit.key(BuildKit.vec(best["p"])) if not best.is_empty() else ""
		last_r = int(best.get("r", -1))
	return best


## (Snapping) A socket already filled by a piece of this kind.
func _taken(kind: String, I: Dictionary, at: Vector3) -> bool:
	var k := BuildKit.key(at)
	match kind:
		"plate":
			return _plate.has(k)
		"edge":
			return not (I.get("ladder", false) or I.get("outside", false)) and _edge.has(k)
		"corner":
			return _corner.has(k)
		"cell":
			return _cell.has(k)
	return false


## A plate of shape `sh` against the edge a..b (`n` out from it): its places
## [anchor, turn, judged-by point] - centred on an edge its width, side by side
## along a longer one (a quarter twice along a cell's edge), an end lined up on a
## shorter one; a half against it by its long side, or (turned) its short one.
static func attach(sh: String, a: Vector3, b: Vector3, n: Vector3, turned: int, lift: Vector3) -> Array:
	var L := Vector2(b.x - a.x, b.z - a.z).length()
	var ex := BuildKit.extent(sh)
	var W := ex.x * 2.0
	var D := ex.y * 2.0
	var r := BuildKit.r_facing(n)
	if sh == "tri":
		D = BuildKit.TRI_R * 2.0
	elif sh == "half" and turned % 2 == 1:
		W = ex.y * 2.0
		D = ex.x * 2.0
		r = BuildKit.r_along(n)   # (its long side out from the edge)
	var dir := (b - a).normalized()
	var offs := []
	if absf(W - L) < 0.1:
		offs = [0.0]
	elif W < L:
		for k in roundi(L / W):
			offs.append(-L * 0.5 + W * 0.5 + k * W)
	else:
		offs = [(W - L) * 0.5, -(W - L) * 0.5]
	var out := []
	for o: float in offs:
		var at: Vector3 = (a + b) * 0.5 + dir * o + n * (D * 0.5)
		out.append([at, r, at + lift])
	return out


## A piece of furniture where you aim: on a floor, set square to it on a half metre
## grid; a wall lamp on the wall's face; on the ground, as it is.
func snap_free(id: String, aim: Vector3, turned := 0, free := false) -> Dictionary:
	if BuildKit.info(id).get("wallfix", false):
		var lv := floorf((aim.y + 0.2) / BuildKit.WALL_H) * BuildKit.WALL_H
		var w := wall_near(Vector3(aim.x, lv, aim.z), 1.2)
		if w < 0:
			w = wall_near(Vector3(aim.x, lv - BuildKit.WALL_H, aim.z), 1.2)
		if w < 0:
			return {}
		var pw: Dictionary = pieces[w]
		var base := BuildKit.vec(pw["p"])
		var b := BuildKit.turn(int(pw.get("r", 0)))
		var l := b.inverse() * (aim - base)
		var side := 1.0 if l.z >= 0.0 else -1.0
		var x := clampf(snappedf(l.x, 0.5), -1.5, 1.5)
		var at := base + b * Vector3(x, 0, side * (BuildKit.WALL_T * 0.5 + 0.07))
		return {"t": id, "p": BuildKit.arr(at), "r": posmod(int(pw.get("r", 0)) + (0 if side > 0.0 else 6), 12)}
	var j := plate_under(Vector3(aim.x, aim.y, aim.z)) if not free else -1
	if j < 0:
		for dy: float in [0.15, -0.15, 0.3]:
			j = plate_under(Vector3(aim.x, snappedf(aim.y + dy, 0.25), aim.z)) if not free else -1
			if j >= 0:
				break
	if j >= 0:
		var pj: Dictionary = pieces[j]
		var o := BuildKit.vec(pj["p"])
		var b := BuildKit.turn(int(pj.get("r", 0)))
		var l := b.inverse() * (aim - o)
		var at := o + b * Vector3(snappedf(l.x, 0.5), 0, snappedf(l.z, 0.5))
		return {"t": id, "p": BuildKit.arr(at), "r": posmod(int(pj.get("r", 0)) + 3 * turned, 12)}
	return {"t": id, "p": BuildKit.arr(aim), "r": posmod(turned, 12)}


# --- Can it go there? ------------------------------------------------------------------

## Why piece `pc` can't go where it is ("": it can) - its socket taken,
## something in the way, the ground, nothing holding it up. Sets a
## foundation's depth (`d`) to reach the ground.
func check(pc: Dictionary) -> String:
	var id := str(pc["t"])
	var I := BuildKit.info(id)
	var p := BuildKit.vec(pc["p"])
	var k := BuildKit.key(p)
	var up := Vector3(0, BuildKit.WALL_H, 0)
	match str(I["kind"]):
		"plate":
			if _plate.has(k):
				return "There's one there already"
			var mine := BuildKit.corners(pc)
			for j in _plates_y.get(_yk(p.y), []):
				if _overlap(mine, BuildKit.corners(pieces[j])):
					return "It overlaps another"
			if _cell.has(BuildKit.key(p - up)) and str(pieces[_cell[BuildKit.key(p - up)]]["t"]) != "ladder":
				return "The stairs come up here"
			if I.get("found", false):
				var lo := INF
				var hi := -INF
				var c := Vector3.ZERO
				for q: Vector3 in mine:
					var g := _ground_at(q.x, q.z)
					lo = minf(lo, g)
					hi = maxf(hi, g)
					c += q
				c /= mine.size()
				var gm := _ground_at(c.x, c.z)
				lo = minf(lo, gm)
				hi = maxf(hi, gm)
				if hi > p.y + 0.6:
					return "The ground's too high here - dig it down"
				if p.y - lo > 7.0:
					return "Too steep - the ground falls away"
				pc["d"] = snappedf(maxf(0.8, p.y - lo + 0.6), 0.01)
		"edge":
			if I.get("ladder", false) or I.get("outside", false):
				if _ladder.has(_ladder_key(pc)):
					return "There's one there already"
			elif _edge.has(k):
				return "There's one there already"
		"corner":
			if _corner.has(k):
				return "There's one there already"
		"cell":
			if _cell.has(k):
				return "There's one there already"
			if _plate.has(BuildKit.key(p + up)):
				return "No headroom - a ceiling over it"
		"free":
			for j in _free:
				if BuildKit.vec(pieces[j]["p"]).distance_to(p) < 0.7:
					return "Too close to another"
	var s := support(pc)
	if s <= 0:
		if I["kind"] == "plate" and not I.get("found", false):
			var n := BuildKit.span_of(int(pc.get("m", 1))) - 1
			return "Too far from a support - %s reaches %d cell%s past a wall or pillar" % [BuildKit.tier_name(int(pc.get("m", 1))).to_lower(), n, "" if n == 1 else "s"]
		return "Nothing holds it up"
	return ""


## Two outlines (convex, at one height) overlap - not just touch.
static func _overlap(a: Array, b: Array) -> bool:
	for poly in [a, b]:
		for i in poly.size():
			var p0: Vector3 = poly[i]
			var p1: Vector3 = poly[(i + 1) % poly.size()]
			var n := Vector2(p1.z - p0.z, -(p1.x - p0.x)).normalized()
			var amin := INF
			var amax := -INF
			var bmin := INF
			var bmax := -INF
			for q: Vector3 in a:
				var d := n.dot(Vector2(q.x, q.z))
				amin = minf(amin, d)
				amax = maxf(amax, d)
			for q: Vector3 in b:
				var d := n.dot(Vector2(q.x, q.z))
				bmin = minf(bmin, d)
				bmax = maxf(bmax, d)
			if amax <= bmin + 0.05 or bmax <= amin + 0.05:
				return false
	return true


# --- Changes ---------------------------------------------------------------------------

func add(pc: Dictionary) -> int:
	pieces.append(pc)
	reindex()
	return pieces.size() - 1


## Takes piece `i` away, and what falls with it: the records taken (the first piece `i`'s).
func remove(i: int) -> Array:
	var gone := falling(i)
	gone.sort()
	var out := []
	for j in range(gone.size() - 1, -1, -1):
		out.push_front(pieces[gone[j]])
		pieces.remove_at(gone[j])
	# (piece i first in the list)
	var first: Dictionary = out[gone.find(i)]
	out.erase(first)
	out.push_front(first)
	reindex()
	return out


# --- Picking ---------------------------------------------------------------------------

## The piece a ray (frame's) meets first within `limit`: [index, t] or [-1, INF].
func pick(o: Vector3, d: Vector3, limit: float) -> Array:
	var best := -1
	var bt := limit
	for i in pieces.size():
		var box := pick_box(i)
		var b := BuildKit.turn(int(pieces[i].get("r", 0)))
		var c: Vector3 = box[0]
		var lo := b.inverse() * (o - c)
		var ld := b.inverse() * d
		var t := CosmosSolids._ray_box(lo, ld, AABB(-(box[1] as Vector3), (box[1] as Vector3) * 2.0), bt)
		if t < bt:
			bt = t
			best = i
	return [best, bt]


## A piece's box for picking: [middle (frame), half size (its own axes)].
func pick_box(i: int) -> Array:
	var pc: Dictionary = pieces[i]
	var id := str(pc["t"])
	var I := BuildKit.info(id)
	var p := BuildKit.vec(pc["p"])
	var h := BuildKit.CELL * 0.5
	match str(I["kind"]):
		"plate":
			var ex := BuildKit.extent(str(I["shape"]))
			if I.get("roof", false):
				return [p + Vector3(0, BuildKit.RISE * 0.45, 0), Vector3(ex.x, BuildKit.RISE * 0.5, ex.y)]
			if I.get("found", false):
				return [p - Vector3(0, 0.3, 0), Vector3(ex.x, 0.3, ex.y)]
			return [p - Vector3(0, BuildKit.SLAB * 0.5, 0), Vector3(ex.x, BuildKit.SLAB * 0.5 + 0.02, ex.y)]
		"edge":
			if id == "steps":
				return [p + BuildKit.turn(int(pc.get("r", 0))) * Vector3(0, -0.3, 0.8), Vector3(1.3, 0.3, 0.7)]
			if I.get("ladder", false):
				return [p + BuildKit.turn(int(pc.get("r", 0))) * Vector3(0, 1.6, 0.3), Vector3(0.35, 1.6, 0.15)]
			var ht := BuildKit.height(id)
			if I.get("hang", false):
				return [p + Vector3(0, BuildKit.H - 0.5, 0), Vector3(h - 0.2, 0.5, 0.2)]
			if I.get("beam", false):
				return [p + Vector3(0, BuildKit.H - 0.3, 0), Vector3(h - 0.25, 0.3, 0.2)]
			if I.get("gable", false):
				return [p + Vector3(0, BuildKit.RISE * 0.5 - 0.1, 0), Vector3(h - 0.2, BuildKit.RISE * 0.5, 0.2)]
			ht = minf(ht, BuildKit.H)
			return [p + Vector3(0, ht * 0.5, 0), Vector3(h - 0.2, ht * 0.5, 0.2)]
		"corner":
			return [p + Vector3(0, BuildKit.H * 0.5, 0), Vector3(0.3, BuildKit.H * 0.5, 0.3)]
		"cell":
			return [p + Vector3(0, BuildKit.WALL_H * 0.5, 0), Vector3(h - 0.3, BuildKit.WALL_H * 0.5, h - 0.3)]
	if I.get("wallfix", false):
		return [p + BuildKit.turn(int(pc.get("r", 0))) * Vector3(0, 1.95, 0.2), Vector3(0.2, 0.3, 0.2)]
	return [p + Vector3(0, 0.5, 0), Vector3(0.6, 0.5, 0.6)]


## Where the walls meet: a post at each end of a wall, fence or doorway (not
## where there's a pillar): [at (frame, its foot), height, tier, style, turn].
func posts() -> Array:
	var at := {}
	for k in _edge:
		var i: int = _edge[k]
		if not _is(i, "post"):
			continue
		var pc: Dictionary = pieces[i]
		var h := 1.15 if _is(i, "low") else BuildKit.H
		for e in BuildKit.ends(pc):
			var key := BuildKit.key(e)
			if _corner.has(key):
				continue
			if not at.has(key) or float(at[key][1]) < h:
				at[key] = [e, h, int(pc.get("m", 1)), str(pc.get("s", "minoa")), int(pc.get("r", 0))]
	return at.values()
