class_name CosmosHullGrid
extends RefCounted
## A ship's hull as a solid, for walking round it (the 3D game: a landed ship -
## a town's field's shuttle, a port's trader, your own): a grid of CELL m
## cells over its design in the ship's own space, each the signed distance to
## its skin (negative inside; in 1/Q of a cell, a byte), made once a design and
## size on a worker and shared by every ship that wears it. Made from the hull's
## triangles: the cells they pass through marked, the outside flooded in from
## the grid's edges (6-connected), what it doesn't reach solid; then the exact
## distances to the nearest cell of the other kind (Felzenszwalb's separable
## transform, three passes). Looked up with trilinear weights - O(1) a probe:
##   push - a body's ball held out of it along the ground (Cosmos._hull_bump);
##   top_below - its top under you, stood on (a wing, the hull's back);
##   ray - the camera's line, a bolt's segment, where it first meets it.
## The doorway (a ship's ramp down, its insides made) is the callers' to leave
## open: `door`, a box in the ship's space no probe in it is held out of.
##   var g := CosmosHullGrid.of(ship)    # (null until made - started then)

const CELL := 0.4              # m: a cell (a big ship's grow to keep within MAX_CELLS)
const MAX_CELLS := 900000
const PAD := 2                 # cells of open space round the hull
const Q := 16.0                # the distances' steps a cell (bytes: +-127 - out to ~8 cells)
const FAR := 1e9

static var _cache := {}        # key -> {"task": job id (-1: none), "out": {} (the worker's), "grid": CosmosHullGrid, "src": its triangles while queued}
static var _stop: Array = [false]

var cell := CELL
var org := Vector3.ZERO        # the grid's low corner (ship space); cell (i, j, k)'s middle at org + (i + 0.5) * cell
var nx := 0
var ny := 0
var nz := 0
var sdf := PackedByteArray()   # signed, Q steps a cell
var bounds := AABB()           # the solid's (ship space)
var solid := 0                 # its cells (the tests, the notes)
var ms := 0                    # its build (ms, on its worker)


# --- Made once a design and size -------------------------------------------------------------

## The grid of `ship`'s hull (its meshes with their "verts" or "hull_verts" meta - its
## body, its glass; not the gear, not the insides - in its own space), or null while
## it's made (asked for the first time: queued for a worker - one made at a time).
static func of(ship: Node3D) -> CosmosHullGrid:
	if ship.has_meta("hull_grid"):
		return ship.get_meta("hull_grid")
	var key := str(ship.get_meta("hull_grid_key", ""))
	if key == "" or not _cache.has(key):
		var src := _sources(ship)
		if src.is_empty():
			return null
		key = src[0]
		ship.set_meta("hull_grid_key", key)
		if not _cache.has(key):
			_cache[key] = {"task": -1, "out": {}, "grid": null, "src": [src[1], src[2]]}
			_queue.append(key)
	_pump()
	var e: Dictionary = _cache[key]
	if e["grid"] == null:
		if e.has("src") or not Jobs.done(int(e["task"])):
			return null   # (queued, or being made)
		Jobs.wait(int(e["task"]))
		e["task"] = -1
		if (e["out"] as Dictionary).is_empty():
			_cache.erase(key)   # (given up - its world left as it was made: made again when asked)
			return null
		e["grid"] = _from(e["out"])
		e["out"] = {}
	var g: CosmosHullGrid = e["grid"]
	ship.set_meta("hull_grid", g)
	return g


## Made now if it isn't (tests): waited for.
static func now(ship: Node3D) -> CosmosHullGrid:
	var g := of(ship)
	if g == null and ship.has_meta("hull_grid_key"):
		var key := str(ship.get_meta("hull_grid_key"))
		var e: Dictionary = _cache.get(key, {})
		if e.has("src"):
			_queue.erase(key)
			_run(key)
			_running = key
		if int(e.get("task", -1)) >= 0:
			Jobs.wait(int(e["task"]))
			e["task"] = -1
			if _running == key:
				_running = ""
			if not (e["out"] as Dictionary).is_empty():
				e["grid"] = _from(e["out"])
				e["out"] = {}
		g = of(ship)
	return g


static var _queue: Array = []   # keys waiting for a worker
static var _running := ""       # the one being made


## The next queued grid started once the last is done (one at a time: a big one takes a
## worker a few seconds - never several of them holding the pool's low-priority threads).
static func _pump() -> void:
	if _running != "":
		var e: Dictionary = _cache.get(_running, {})
		if not e.is_empty() and int(e["task"]) >= 0 and not Jobs.done(int(e["task"])):
			return
		_running = ""
	while not _queue.is_empty():
		var key: String = _queue.pop_front()
		if _cache.has(key) and (_cache[key] as Dictionary).has("src"):
			_run(key)
			_running = key
			return


static func _run(key: String) -> void:
	var e: Dictionary = _cache[key]
	var src: Array = e["src"]
	e.erase("src")
	var out: Dictionary = e["out"]
	var stop := _stop
	e["task"] = Jobs.add(func(): out.merge(make(src[0], src[1], stop)), false, "hull grid")


## [key, triangles (ship space), seal triangles] of a ship's hull - or [] (no hull mesh yet).
static func _sources(ship: Node3D) -> Array:
	var tris := []
	var seal := []
	var key := ""
	for mi: MeshInstance3D in ship.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or not (mi.mesh.has_meta("verts") or mi.mesh.has_meta("hull_verts")) or mi.has_meta("gear") or _inside(mi, ship):
			continue
		var xf := Transform3D()
		var n: Node = mi
		while n != ship and n != null:
			xf = (n as Node3D).transform * xf
			n = n.get_parent()
		tris.append([mi.mesh.get_meta("verts") if mi.mesh.has_meta("verts") else mi.mesh.get_meta("hull_verts"), xf])
		if mi.mesh.has_meta("seal"):
			seal.append([mi.mesh.get_meta("seal"), xf])
		key += "%d@%s;" % [mi.mesh.get_instance_id(), str(xf)]
	return [key, tris, seal] if not tris.is_empty() else []


static func _inside(n: Node, ship: Node) -> bool:
	var p := n.get_parent()
	while p != null and p != ship:
		if p is CosmosNpcInterior or p is CosmosShipInterior:
			return true
		p = p.get_parent()
	return false


## Every build collected (leaving the game, the tests: no task left running) - given up halfway.
static func finish_tasks() -> void:
	_stop[0] = true
	for k in _cache.keys():
		var e: Dictionary = _cache[k]
		if int(e["task"]) >= 0:
			Jobs.wait(int(e["task"]))
			e["task"] = -1
		if e["grid"] == null and (e["out"] as Dictionary).is_empty():
			_cache.erase(k)   # (given up, or never started: made again when asked)
	_queue.clear()
	_running = ""
	_stop = [false]


static func _from(out: Dictionary) -> CosmosHullGrid:
	var g := CosmosHullGrid.new()
	if out.is_empty():
		return g
	g.cell = out["cell"]
	g.org = out["org"]
	g.nx = out["nx"]
	g.ny = out["ny"]
	g.nz = out["nz"]
	g.sdf = out["sdf"]
	g.bounds = out["bounds"]
	g.solid = out["solid"]
	g.ms = out["ms"]
	return g


## (A worker's) The grid of triangles `tris` ([[verts, to ship space]...]); `seal` - more
## triangles closing a doorway the mesh leaves open (solid, not drawn).
static func make(tris: Array, seal: Array, stop: Array = [false]) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var all := PackedVector3Array()
	for src in tris + seal:
		var vs: PackedVector3Array = src[0]
		var xf: Transform3D = src[1]
		var base := all.size()
		all.resize(base + vs.size())
		for i in vs.size():
			all[base + i] = xf * vs[i]
	if all.size() < 3:
		return {}
	var box := AABB(all[0], Vector3.ZERO)
	for p in all:
		box = box.expand(p)
	var cell := maxf(CELL, pow(box.size.x * box.size.y * box.size.z / MAX_CELLS, 1.0 / 3.0) * 1.02)
	var org := box.position - Vector3.ONE * (PAD * cell)
	var nx := int(ceil(box.size.x / cell)) + PAD * 2 + 1
	var ny := int(ceil(box.size.y / cell)) + PAD * 2 + 1
	var nz := int(ceil(box.size.z / cell)) + PAD * 2 + 1
	var nxy := nx * ny
	var total := nxy * nz
	var occ := PackedByteArray()
	occ.resize(total)   # (0 open, 1 skin, 2 outside)
	# The skin: each triangle sampled at half a cell - the cells it passes through.
	var inv := 1.0 / cell
	var half := cell * 0.5
	var k := 0
	while k + 2 < all.size():
		if (k & 1023) == 0 and stop[0]:
			return {}
		var a := (all[k] - org) * inv
		var b := (all[k + 1] - org) * inv
		var c := (all[k + 2] - org) * inv
		k += 3
		var n := int(ceil(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) * 2.0))
		if n <= 0:
			occ[int(a.x) + nx * (int(a.y) + ny * int(a.z))] = 1
			continue
		var ab := (b - a) / n
		var ac := (c - a) / n
		for i in n + 1:
			var p := a + ab * i
			for j in n + 1 - i:
				occ[int(p.x) + nx * (int(p.y) + ny * int(p.z))] = 1
				p += ac
	# The outside: flooded in from the grid's faces (the pad keeps them open, one space) - its
	# outer layer marked, the one inside it the seeds: every cell popped has all six neighbours.
	var stack := PackedInt32Array()
	stack.resize(maxi(total / 4, 4096))
	var top := 0
	for z in nz:
		for y in ny:
			for x in nx:
				var i := x + nx * (y + ny * z)
				if x == 0 or y == 0 or z == 0 or x == nx - 1 or y == ny - 1 or z == nz - 1:
					occ[i] = 2
				elif (x == 1 or y == 1 or z == 1 or x == nx - 2 or y == ny - 2 or z == nz - 2) and occ[i] == 0:
					occ[i] = 2
					if top >= stack.size():
						stack.resize(stack.size() * 2)
					stack[top] = i
					top += 1
	var steps := 0
	while top > 0:
		top -= 1
		var i := stack[top]
		steps += 1
		if (steps & 65535) == 0 and stop[0]:
			return {}
		if top + 6 >= stack.size():
			stack.resize(stack.size() * 2)
		var j := i - 1
		if occ[j] == 0:
			occ[j] = 2
			stack[top] = j
			top += 1
		j = i + 1
		if occ[j] == 0:
			occ[j] = 2
			stack[top] = j
			top += 1
		j = i - nx
		if occ[j] == 0:
			occ[j] = 2
			stack[top] = j
			top += 1
		j = i + nx
		if occ[j] == 0:
			occ[j] = 2
			stack[top] = j
			top += 1
		j = i - nxy
		if occ[j] == 0:
			occ[j] = 2
			stack[top] = j
			top += 1
		j = i + nxy
		if occ[j] == 0:
			occ[j] = 2
			stack[top] = j
			top += 1
	# The distances (squared, in cells): from each outside cell to the nearest solid one,
	# from each solid one to the nearest outside.
	var d_out := PackedFloat32Array()
	var d_in := PackedFloat32Array()
	d_out.resize(total)
	d_in.resize(total)
	var solid := 0
	var lo := Vector3i(nx, ny, nz)
	var hi := Vector3i(-1, -1, -1)
	for i in total:
		if occ[i] == 2:
			d_out[i] = FAR
			d_in[i] = 0.0
		else:
			d_out[i] = 0.0
			d_in[i] = FAR
			solid += 1
			var x := i % nx
			var y := (i / nx) % ny
			var z := i / nxy
			lo = Vector3i(mini(lo.x, x), mini(lo.y, y), mini(lo.z, z))
			hi = Vector3i(maxi(hi.x, x), maxi(hi.y, y), maxi(hi.z, z))
	for f in [d_out, d_in]:
		if stop[0]:
			return {}
		_edt(f, nx, ny, nz)
	var sdf := PackedByteArray()
	sdf.resize(total)
	for i in total:
		var s: float = sqrt(d_out[i]) if occ[i] == 2 else 1.0 - sqrt(d_in[i])   # (its skin through the middles of its outermost cells: a triangle's cell has it somewhere in it)
		sdf[i] = clampi(roundi(s * Q), -127, 127) & 255
	var bounds := AABB(org + Vector3(lo) * cell, Vector3(hi - lo + Vector3i.ONE) * cell)
	return {"cell": cell, "org": org, "nx": nx, "ny": ny, "nz": nz, "sdf": sdf, "bounds": bounds, "solid": solid,
		"ms": Time.get_ticks_msec() - t0}


## The squared distance transform of `f` (0 at the cells measured from, FAR elsewhere) in
## place: a 1D pass along each axis (the lower envelope of parabolas).
static func _edt(f: PackedFloat32Array, nx: int, ny: int, nz: int) -> void:
	var dims := [nx, ny, nz]
	var strides := [1, nx, nx * ny]
	for ax in 3:
		var n: int = dims[ax]
		var st: int = strides[ax]
		var line := PackedFloat32Array()
		line.resize(n)
		var out := PackedFloat32Array()
		out.resize(n)
		var v := PackedInt32Array()
		v.resize(n)
		var zz := PackedFloat32Array()
		zz.resize(n + 1)
		# (every line along this axis: its start over the other two)
		var oa: int = dims[(ax + 1) % 3]
		var ob: int = dims[(ax + 2) % 3]
		var sa: int = strides[(ax + 1) % 3]
		var sb: int = strides[(ax + 2) % 3]
		for b in ob:
			for a in oa:
				var base: int = a * sa + b * sb
				var src := false
				var left := false
				for q in n:
					var fv := f[base + q * st]
					line[q] = fv
					if fv < FAR:
						src = true
					if fv > 0.0:
						left = true
				if not src or not left:
					continue   # (nothing to measure from - or all of it measured from: as it is)
				var kk := 0
				v[0] = 0
				zz[0] = -FAR
				zz[1] = FAR
				for q in range(1, n):
					var fq := line[q]
					if fq >= FAR:
						continue
					if line[v[0]] >= FAR:
						v[0] = q
						continue
					var s := ((fq + q * q) - (line[v[kk]] + v[kk] * v[kk])) / (2.0 * (q - v[kk]))
					while s <= zz[kk]:
						kk -= 1
						s = ((fq + q * q) - (line[v[kk]] + v[kk] * v[kk])) / (2.0 * (q - v[kk]))
					kk += 1
					v[kk] = q
					zz[kk] = s
					zz[kk + 1] = FAR
				kk = 0
				for q in n:
					while zz[kk + 1] < q:
						kk += 1
					var dq := q - v[kk]
					out[q] = dq * dq + line[v[kk]]
				for q in n:
					f[base + q * st] = out[q]


# --- Looked up (ship space) --------------------------------------------------------------------

func _at(i: int, j: int, k: int) -> float:
	if i < 0 or j < 0 or k < 0 or i >= nx or j >= ny or k >= nz:
		return PAD
	var b := sdf[i + nx * (j + ny * k)]
	return float(b if b < 128 else b - 256) / Q


## The signed distance (m) from `p` to the hull's skin (negative inside) and its
## gradient (the way out): Vector4(gx, gy, gz, distance) - the grid's trilinear blend;
## `door` (if not empty) a box cut out of it (its doorway, open).
func probe(p: Vector3, door := AABB()) -> Vector4:
	var v := _blend(p)
	if door.size != Vector3.ZERO:
		var b := _box(p, door)
		if -b.w > v.w:
			return -b
	return v


## A box's signed distance from `p` and its gradient (as probe's).
static func _box(p: Vector3, b: AABB) -> Vector4:
	var c := b.get_center()
	var h := b.size * 0.5
	var l := p - c
	var q := l.abs() - h
	var o := Vector3(maxf(q.x, 0.0), maxf(q.y, 0.0), maxf(q.z, 0.0))
	var ol := o.length()
	if ol > 0.0:
		var gr := Vector3(o.x * signf(l.x), o.y * signf(l.y), o.z * signf(l.z)) / ol
		return Vector4(gr.x, gr.y, gr.z, ol)
	var a := 0 if q.x >= q.y and q.x >= q.z else (1 if q.y >= q.z else 2)
	var gi := Vector3.ZERO
	gi[a] = 1.0 if l[a] >= 0.0 else -1.0
	return Vector4(gi.x, gi.y, gi.z, q[a])


func _blend(p: Vector3) -> Vector4:
	var g := (p - org) / cell - Vector3(0.5, 0.5, 0.5)
	if g.x < -1.0 or g.y < -1.0 or g.z < -1.0 or g.x > nx or g.y > ny or g.z > nz:
		return Vector4(0, 0, 0, _box(p, AABB(org, Vector3(nx, ny, nz) * cell)).w + PAD * cell)   # (off its grid: at least this far)
	var i := floori(g.x)
	var j := floori(g.y)
	var k := floori(g.z)
	var fx := g.x - i
	var fy := g.y - j
	var fz := g.z - k
	var c000 := _at(i, j, k)
	var c100 := _at(i + 1, j, k)
	var c010 := _at(i, j + 1, k)
	var c110 := _at(i + 1, j + 1, k)
	var c001 := _at(i, j, k + 1)
	var c101 := _at(i + 1, j, k + 1)
	var c011 := _at(i, j + 1, k + 1)
	var c111 := _at(i + 1, j + 1, k + 1)
	var x00 := lerpf(c000, c100, fx)
	var x10 := lerpf(c010, c110, fx)
	var x01 := lerpf(c001, c101, fx)
	var x11 := lerpf(c011, c111, fx)
	var y0 := lerpf(x00, x10, fy)
	var y1 := lerpf(x01, x11, fy)
	var d := lerpf(y0, y1, fz)
	var gx := lerpf(lerpf(c100 - c000, c110 - c010, fy), lerpf(c101 - c001, c111 - c011, fy), fz)
	var gy := lerpf(x10 - x00, x11 - x01, fz)
	var gz := y1 - y0
	return Vector4(gx, gy, gz, d * cell)


## The distance (m) from `p` to its skin (negative inside).
func dist(p: Vector3, door := AABB()) -> float:
	return probe(p, door).w


## Inside it (or within `m` of its skin).
func hits(p: Vector3, m := 0.0, door := AABB()) -> bool:
	if not bounds.grow(m + cell).has_point(p):
		return false
	return probe(p, door).w < m


## How far to move a ball (at `p`, radius `r`) out of it along the ground (`up` its up,
## ship space): out across the skin's slope (a plane's way out, as far as it takes),
## nothing where the skin's level (under you a floor - top_below's; over you a roof).
func push(p: Vector3, r: float, up := Vector3.UP, door := AABB()) -> Vector3:
	if not bounds.grow(r + cell).has_point(p):
		return Vector3.ZERO
	var pr := probe(p, door)
	if pr.w >= r:
		return Vector3.ZERO
	var n := Vector3(pr.x, pr.y, pr.z)
	var nl := n.length()
	if nl < 1e-4:
		# (deep in it - past what its cells measure: a ship come down on you) out from its middle, a few cells a go
		var o := p - bounds.get_center()
		o -= up * o.dot(up)
		return o.normalized() * cell * 4.0 if o.length() > 1e-3 else Vector3.ZERO
	n /= nl
	var h := n - up * n.dot(up)
	var hl := h.length()
	if hl >= 0.3:
		return h / hl * ((r - pr.w) / hl)
	if n.dot(up) > 0.0:
		return Vector3.ZERO   # (its skin level under the ball: a floor - top_below's)
	return _escape(p, r, up, door)   # (a roof low over you - under a belly too low for you: out from under it)


## Out from under a low roof of it: toward its nearest open side along the ground (8 ways,
## further and further), a cell a go.
func _escape(p: Vector3, r: float, up: Vector3, door: AABB) -> Vector3:
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	var s := cell
	while s < 24.0:
		for k in 8:
			var d := side.rotated(up, k * PI * 0.25)
			if dist(p + d * s, door) > r:
				return d * minf(s, cell)
		s += cell
	return Vector3.ZERO


## Its top under `p` (ship space, y up): the highest skin under it no higher than `step`
## over it - ship-space y, or -INF (nothing there: open to the ground).
func top_below(p: Vector3, step: float, door := AABB()) -> float:
	if p.x < bounds.position.x or p.z < bounds.position.z or p.x > bounds.end.x or p.z > bounds.end.z:
		return -INF
	var y := p.y + step
	if y < bounds.position.y:
		return -INF
	y = minf(y, bounds.end.y + cell)
	var above := dist(Vector3(p.x, y, p.z), door)
	if above < 0.0:
		return -INF   # (in it to over a step's height: a wall, not a floor)
	while y > bounds.position.y - cell:
		var y2 := y - cell * 0.5
		var d := dist(Vector3(p.x, y2, p.z), door)
		if d < 0.0:
			return y2 + (y - y2) * (-d) / maxf(above - d, 1e-4)   # (the crossing between the two)
		above = d
		y = y2
	return -INF


## Where the ray `o` + `d` t (ship space, `d` a unit) first meets it within `limit`, or INF:
## stepped along by the distance (never under a quarter cell, never through it).
func ray(o: Vector3, d: Vector3, limit: float, door := AABB()) -> float:
	# (from where the line comes into its box - or INF, it misses it)
	var inv := Vector3(1.0 / d.x if absf(d.x) > 1e-9 else 1e9, 1.0 / d.y if absf(d.y) > 1e-9 else 1e9, 1.0 / d.z if absf(d.z) > 1e-9 else 1e9)
	var b := bounds.grow(cell)
	var ta := (b.position - o) * inv
	var tb := (b.end - o) * inv
	var t := maxf(maxf(maxf(minf(ta.x, tb.x), minf(ta.y, tb.y)), minf(ta.z, tb.z)), 0.0)
	var t1 := minf(minf(maxf(ta.x, tb.x), maxf(ta.y, tb.y)), maxf(ta.z, tb.z))
	if t1 < t or t > limit:
		return INF
	limit = minf(limit, t1)
	var n := 0
	while t <= limit and n < 256:
		var s := dist(o + d * t, door)
		if s < 0.02:
			return t
		t += maxf(s, cell * 0.25)
		n += 1
	return INF


## A fingerprint of its cells (the tests: the same design, the same grid).
func digest() -> int:
	return hash(sdf) ^ hash([nx, ny, nz, cell, org])
