class_name CosmosSolids
extends Node3D
## What's solid in a built place you walk through - a town's buildings
## (CosmosTown), a structure of your own (CosmosStructure): blocks in its frame
## (y up), each an AABB (the fast, common case) or a Prism (a convex outline
## on the ground, its foot and top: a wall turned 30 degrees, a triangle of
## floor, a step of a spiral stair; its top may slope - a roof, a ramp),
## gathered in a grid of GRID m cells. The same blocks are floors (what's
## under your feet that's not above them + STEP: stairs, roofs, ceilings),
## walls (a body pushed out of them along the ground), the ship's hull's
## and the camera's obstacles. No physics bodies: plain geometry, looked up
## in the grid's cell.

const STEP := 0.7              # m: walked up onto (stairs); higher blocks
const GRID := 8.0              # the solids' grid
const BODY_H := 1.8

var _solids: Array = []        # [AABB or Prism] (local)
var _grid := {}                # Vector2i -> PackedInt32Array
var ground := 0.0              # (the floor where there's no block: a town's levelled ground; -INF: the world's own)


## A convex block: `poly` its outline (x, z - any winding), y0 its foot, y1 its
## top - or, with `planes`, its top a slope: each plane (a, b, c) a height
## a x + b z + c, the top the lowest of them (mode 1: a hip's ridge) or the
## highest (mode 2: a valley), clamped to y0 .. y1.
class Prism:
	var poly := PackedVector2Array()
	var nrm := PackedVector2Array()   # (each edge's outward normal)
	var y0 := 0.0
	var y1 := 0.0
	var planes: Array = []           # [Vector3(a, b, c)]
	var mode := 0
	var rect := Rect2()

	func _init(p: PackedVector2Array, a: float, b: float, pl: Array = [], m := 0) -> void:
		y0 = a
		y1 = b
		planes = pl
		mode = m
		var c := Vector2.ZERO
		for q in p:
			c += q
		c /= maxf(1.0, p.size())
		# (counter-clockwise, seen from above with x right and z down the page: the normals out)
		var area := 0.0
		for i in p.size():
			var u := p[i]
			var v := p[(i + 1) % p.size()]
			area += u.x * v.y - v.x * u.y
		poly = p if area > 0.0 else _reversed(p)
		for i in poly.size():
			var e := poly[(i + 1) % poly.size()] - poly[i]
			var n := Vector2(e.y, -e.x).normalized()
			if n.dot(poly[i] - c) < 0.0:
				n = -n
			nrm.append(n)
		rect = Rect2(poly[0], Vector2.ZERO)
		for q in poly:
			rect = rect.expand(q)

	static func _reversed(p: PackedVector2Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for i in range(p.size() - 1, -1, -1):
			out.append(p[i])
		return out

	## How far inside (> 0) - the least depth past any edge; < 0 outside.
	func depth(x: float, z: float) -> float:
		var d := INF
		var q := Vector2(x, z)
		for i in poly.size():
			d = minf(d, -(q - poly[i]).dot(nrm[i]))
		return d

	func has(x: float, z: float) -> bool:
		return depth(x, z) >= 0.0

	func top_at(x: float, z: float) -> float:
		if planes.is_empty():
			return y1
		var t := INF if mode != 2 else -INF
		for pl: Vector3 in planes:
			var h := pl.x * x + pl.y * z + pl.z
			t = minf(t, h) if mode != 2 else maxf(t, h)
		return clampf(t, y0, y1)

	## The nearest point of its outline to (x, z) - (x, z) itself when inside.
	func nearest(x: float, z: float) -> Vector2:
		var q := Vector2(x, z)
		if has(x, z):
			return q
		var best := q
		var bd := INF
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var ab := b - a
			var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
			var p := a + ab * t
			var d := p.distance_squared_to(q)
			if d < bd:
				bd = d
				best = p
		return best

	func aabb() -> AABB:
		return AABB(Vector3(rect.position.x, y0, rect.position.y), Vector3(rect.size.x, y1 - y0, rect.size.y))

	## Where a ray first enters it (t), or INF.
	func ray(o: Vector3, d: Vector3, limit: float) -> float:
		var t0 := 0.0
		var t1 := limit
		# (its foot and top - a sloped top as its highest: the camera's, a little early on a roof)
		if absf(d.y) < 1e-8:
			if o.y < y0 or o.y > y1:
				return INF
		else:
			var ta := (y0 - o.y) / d.y
			var tb := (y1 - o.y) / d.y
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
		for i in poly.size():
			var n := nrm[i]
			var dn := d.x * n.x + d.z * n.y
			var on := (o.x - poly[i].x) * n.x + (o.z - poly[i].y) * n.y   # (> 0: outside this edge)
			if absf(dn) < 1e-9:
				if on > 0.0:
					return INF
				continue
			var t := -on / dn
			if dn < 0.0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
			if t0 > t1:
				return INF
		return t0 if t0 > 0.0 and t0 <= t1 else INF


## Fewer, longer blocks: boxes lying end to end (the same height and depth,
## within `gap` of each other along x, then z, then up) made one - a building's
## wall pieces along a side one block, its storeys' walls one. Prisms kept as they are.
static func merge_boxes(solids: Array, gap := 0.4) -> Array:
	var boxes: Array = []
	var rest: Array = []
	for s in solids:
		if s is AABB:
			boxes.append(s)
		else:
			rest.append(s)
	for ax in [0, 2, 1]:
		var o1: int = 1 if ax != 1 else 0
		var o2: int = 2 if ax != 2 else 0
		var groups := {}
		for b: AABB in boxes:
			var k := "%d,%d,%d,%d" % [roundi(b.position[o1] * 50.0), roundi(b.end[o1] * 50.0), roundi(b.position[o2] * 50.0), roundi(b.end[o2] * 50.0)]
			if not groups.has(k):
				groups[k] = []
			groups[k].append(b)
		boxes = []
		for k in groups:
			var list: Array = groups[k]
			list.sort_custom(func(a: AABB, b: AABB): return a.position[ax] < b.position[ax])
			var cur: AABB = list[0]
			for i in range(1, list.size()):
				var nb: AABB = list[i]
				if nb.position[ax] <= cur.end[ax] + gap:
					cur = cur.merge(nb)
				else:
					boxes.append(cur)
					cur = nb
			boxes.append(cur)
	return boxes + rest


## The grid over `solids`: Vector2i cell -> the indices of what's in it (a margin of 1 m).
static func grid_of(solids: Array) -> Dictionary:
	var g := {}
	for i in solids.size():
		var b: AABB = solids[i] if solids[i] is AABB else (solids[i] as Prism).aabb()
		for x in range(floori((b.position.x - 1.0) / GRID), floori((b.end.x + 1.0) / GRID) + 1):
			for z in range(floori((b.position.z - 1.0) / GRID), floori((b.end.z + 1.0) / GRID) + 1):
				var k := Vector2i(x, z)
				if not g.has(k):
					g[k] = PackedInt32Array()
				var a: PackedInt32Array = g[k]
				a.append(i)
				g[k] = a
	return g


func _cell(p: Vector3) -> PackedInt32Array:
	return _grid.get(Vector2i(floori(p.x / GRID), floori(p.z / GRID)), PackedInt32Array())


# --- Walking: floors and walls ---------------------------------------------------------

## The highest floor under local `p` that's not above its feet + STEP
## (`ground` where there's none: steps, roofs), local y.
func floor_top(p: Vector3) -> float:
	var best := ground
	for i in _cell(p):
		var s = _solids[i]
		var top: float
		if s is AABB:
			var b: AABB = s
			if p.x < b.position.x or p.z < b.position.z or p.x > b.end.x or p.z > b.end.z:
				continue
			top = b.end.y
		else:
			var pr: Prism = s
			if not pr.rect.has_point(Vector2(p.x, p.z)) or not pr.has(p.x, p.z):
				continue
			top = pr.top_at(p.x, p.z)
		if top <= p.y + STEP and top > best:
			best = top
	return best


## How far to move a body (local `p` its feet, radius `r`, BODY_H tall) out of
## the blocks round it (local, along the ground).
func push(p: Vector3, r: float) -> Vector3:
	var out := Vector3.ZERO
	for i in _cell(p):
		var s = _solids[i]
		var q := p + out
		if s is AABB:
			var b: AABB = s
			if b.end.y <= p.y + STEP or b.position.y >= p.y + BODY_H:
				continue
			var dx0 := q.x - (b.position.x - r)
			var dx1 := (b.end.x + r) - q.x
			var dz0 := q.z - (b.position.z - r)
			var dz1 := (b.end.z + r) - q.z
			if dx0 <= 0.0 or dx1 <= 0.0 or dz0 <= 0.0 or dz1 <= 0.0:
				continue
			var m := minf(minf(dx0, dx1), minf(dz0, dz1))
			if m == dx0:
				out.x -= dx0
			elif m == dx1:
				out.x += dx1
			elif m == dz0:
				out.z -= dz0
			else:
				out.z += dz1
		else:
			out += _push_prism(s, q, r, p.y)
	return out


func _push_prism(pr: Prism, q: Vector3, r: float, feet: float) -> Vector3:
	if pr.y0 >= feet + BODY_H or not pr.rect.grow(r).has_point(Vector2(q.x, q.z)):
		return Vector3.ZERO
	var near := pr.nearest(q.x, q.z)
	if pr.top_at(near.x, near.y) <= feet + STEP:
		return Vector3.ZERO   # (its top within a step where you'd meet it: walked onto, not into)
	var dep := pr.depth(q.x, q.z)
	if dep >= 0.0:   # (inside: out across the nearest edge)
		var bi := 0
		var bd := INF
		for i in pr.poly.size():
			var d := -(Vector2(q.x, q.z) - pr.poly[i]).dot(pr.nrm[i])
			if d < bd:
				bd = d
				bi = i
		var n := pr.nrm[bi]
		return Vector3(n.x, 0.0, n.y) * (bd + r)
	var away := Vector2(q.x, q.z) - near
	var L := away.length()
	if L >= r or L < 1e-6:
		return Vector3.ZERO
	away /= L
	return Vector3(away.x, 0.0, away.y) * (r - L)


## Under a roof or an upper floor (local `p`): indoors.
func indoors(p: Vector3) -> bool:
	return covered(p, 1.9, 6.0)


## Whether a block's foot is over local `p`, between `lo` and `hi` m above it (a
## roof, an upper floor, a window's lintel: covered - not the open top of a wall).
func covered(p: Vector3, lo: float, hi: float) -> bool:
	for i in _cell(p):
		var s = _solids[i]
		var foot: float
		if s is AABB:
			var b: AABB = s
			if not (p.x > b.position.x and p.z > b.position.z and p.x < b.end.x and p.z < b.end.z):
				continue
			foot = b.position.y
		else:
			var pr: Prism = s
			if not pr.has(p.x, p.z):
				continue
			foot = pr.y0
		if foot > p.y + lo and foot < p.y + hi:
			return true
	return false


## How far to move a ball (local `p`, radius `r`) out of the blocks (the ship).
func push_ball(p: Vector3, r: float) -> Vector3:
	var out := Vector3.ZERO
	for i in _cell(p):
		var b: AABB = _solids[i] if _solids[i] is AABB else (_solids[i] as Prism).aabb()
		var q := p + out
		var c := q.clamp(b.position, b.end)
		var d := q - c
		var dl := d.length()
		if dl >= r:
			continue
		if dl > 0.0001:
			out += d / dl * (r - dl)
		else:   # (inside it: out the nearest face)
			var best := INF
			var push := Vector3.ZERO
			for a in 3:
				for sgn: float in [-1.0, 1.0]:
					var depth: float = (b.end[a] - q[a] if sgn > 0.0 else q[a] - b.position[a]) + r
					if depth < best:
						best = depth
						push = Vector3.ZERO
						push[a] = depth * sgn
			out += push
	return out


func is_built() -> bool:
	return not _solids.is_empty()


## The camera's line (Cosmos.camera_clear): where it first meets a block, or INF.
func cam_hit(o: Vector3, dir: Vector3, limit: float) -> float:
	if not is_built():
		return INF
	return ray_hit(to_local(o), global_basis.inverse() * dir, limit)[0]


## A local ray's first block: [t, its index] ([INF, -1]: none within `limit`).
func ray_hit(lo: Vector3, ld: Vector3, limit: float) -> Array:
	var seen := {}
	var best := INF
	var bi := -1
	var steps := int(limit / (GRID * 0.5)) + 1
	for k in mini(steps, 40) + 1:
		var p := lo + ld * minf(k * GRID * 0.5, limit)
		for i in _cell(p):
			if seen.has(i):
				continue
			seen[i] = true
			var s = _solids[i]
			var t := _ray_box(lo, ld, s, minf(limit, best)) if s is AABB else (s as Prism).ray(lo, ld, minf(limit, best))
			if t < best:
				best = t
				bi = i
	return [best, bi]


static func _ray_box(o: Vector3, d: Vector3, b: AABB, limit: float) -> float:
	var t0 := 0.0
	var t1 := limit
	for a in 3:
		if absf(d[a]) < 1e-8:
			if o[a] < b.position[a] or o[a] > b.end[a]:
				return INF
			continue
		var ta := (b.position[a] - o[a]) / d[a]
		var tb := (b.end[a] - o[a]) / d[a]
		if ta > tb:
			var x := ta
			ta = tb
			tb = x
		t0 = maxf(t0, ta)
		t1 = minf(t1, tb)
		if t0 > t1:
			return INF
	return t0 if t0 > 0.0 else INF
