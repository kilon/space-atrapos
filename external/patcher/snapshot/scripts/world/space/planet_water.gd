class_name PlanetWater
extends RefCounted
## A water world's lakes and rivers (PlanetShape.water - sea == 1 worlds): worked
## out once from its ground (make, on a worker, at the planet's setup - its towns
## known: kept off them), then only read (by the workers too).
##
## How: a coarse grid over the sphere (a cube's six faces, ~CELL m a cell) of the
## ground's heights; the water flooded in from the sea, the lowest first (a
## priority flood: every cell drains to the sea, the basins filled to their brims);
## each cell's water down its steepest way; how much flows through each cell (its
## catchment). Cells that gather enough are a river's; the basins deep enough,
## lakes. Each river from its springs (a tributary from where it branches off) to
## the sea, a lake, or the river it joins - smoothed, meandering, a point every
## STEP m - its water's surface stepping down from its spring (never up: the
## lowest of the ground before it), wider and deeper downstream, steep stretches
## fast (rapids), calm ones slow; its bed carved into the ground (carve: a
## channel, its banks shelving up to the land - raised a little where the land
## is lower than its water). Each lake a bowl at its basin's brim, its shore
## wandering, a lip round it to hold it.
##
## Queries (planet-local unit directions / points; any thread): carve (the
## ground's height with the beds cut in - PlanetShape.height), level (the water's
## surface where there's water, else -INF), flow (the current: m/s, planet-local),
## wet (how wet the ground is: 1 under the water, fading up the banks), covered
## (no plants, rocks or sites: the water and its edge). A hash of the river
## points by cells of HCELL m (by their cube-face coordinates) finds the near ones.

const CELL := 46.0             # m: the grid's cells (about)
const STEP := 8.0              # m between a river's points
const HCELL := 24.0            # m: the river points' hash cells
const A_MIN_M2 := 112000.0     # m2 draining through a cell for it to be a river's
const LAKE_MIN := 5            # cells a basin at least, for a lake
const LAKES_MAX := 24
const RIVERS_MAX := 36
const BANK_MAX := 22.0         # m: the banks' widest (deep valleys: their sides cut back)
const FREEBOARD := 0.6         # m: a river's water under its banks
const LIP := 0.5               # m: a lake's lip (and a river's banks) over its water
const FORD := 0.9             # m: water this shallow a road fords
const RAPID_SPEED := 2.2       # m/s: faster than this, rapids (white water, the walker carried off)
const OFF_I := [-1, 0, 1, -1, 1, -1, 0, 1]   # (a cell's 8 neighbours)
const OFF_J := [-1, -1, -1, 0, 0, 1, 1, 1]

var radius := 3000.0
## The rivers' points, all rivers one after another (downstream): planet-local
## metres (at the radius), water surface (m above the radius), half width (m),
## depth at the middle (m), the current (m/s), the river's index.
var pts := PackedVector3Array()
var lvl := PackedFloat32Array()
var hw := PackedFloat32Array()
var dep := PackedFloat32Array()
var spd := PackedFloat32Array()
var along := PackedFloat32Array()   # (m from the river's spring: the shader's flow coordinate)
var rid := PackedInt32Array()
## Each river: {first, count, length, into ("sea", "lake", "river"), from_lake (its index or -1), rapids (m of them), drop (m)}.
var rivers: Array = []
## Each lake: {dir (its middle), level, depth (its deepest), cells, area (m2), reach (m from
## its middle to past its shore), bmax}. Its shape its basin's grid cells': each cell
## near it (its own, and two rings round) kept with its lake (-1: the land round) and how
## far in it is (cells from its shore) - a smooth field from them (_lake_field).
var lakes: Array = []
var _lc_p := PackedVector3Array()     # (the cells' middles, planet-local m)
var _lc_l := PackedInt32Array()       # (its lake, -1 the land round it)
var _lc_b := PackedFloat32Array()     # (cells in from the shore: 1 the shore's)
var _lc_hash := {}                    # cell key (by _lhm) -> PackedInt32Array of those cells
var _lhm := 1
var _lc_size := 40.0                  # (m: the cells' size)
var _lk_level := PackedFloat32Array()
var _lk_depth := PackedFloat32Array()
var _lk_bmax := PackedFloat32Array()
var _shore_n := FastNoiseLite.new()   # (the shores wandering off the cells' lines)
var _hash := {}                       # cell key -> PackedInt32Array of river points
var _hm := 1                          # hash cells a face side
var _reach := PackedFloat32Array()    # (each point's reach: water, banks)
var stats := {}                       # (what make found: counts, lengths - tests, the patch notes)
var _stop: Array = [false]            # (make's: its world gone - give up)

static var _AX: Array = []


static func _axes() -> Array:
	if _AX.is_empty():
		var a: Array = []
		for f in 6:
			a.append(PlanetShape.face_axes(f))
		_AX = a
	return _AX


## The face a unit direction is on.
static func _face(d: Vector3) -> int:
	var ax := absf(d.x)
	var ay := absf(d.y)
	var az := absf(d.z)
	if ax >= ay and ax >= az:
		return 0 if d.x > 0.0 else 1
	if ay >= az:
		return 2 if d.y > 0.0 else 3
	return 4 if d.z > 0.0 else 5


func _key(d: Vector3) -> int:
	return _qkey(d, _hm)


## A unit direction's hash cell, `m` cells a face side (its face, and its place on it).
static func _qkey(d: Vector3, m: int) -> int:
	var ax := absf(d.x)
	var ay := absf(d.y)
	var az := absf(d.z)
	var f := 0
	var a := 0.0
	var b := 0.0
	if ax >= ay and ax >= az:
		f = 0 if d.x > 0.0 else 1
		a = d.y / ax
		b = d.z / ax
	elif ay >= az:
		f = 2 if d.y > 0.0 else 3
		a = d.x / ay
		b = d.z / ay
	else:
		f = 4 if d.z > 0.0 else 5
		a = d.x / az
		b = d.y / az
	return (f * m + clampi(int((b + 1.0) * 0.5 * m), 0, m - 1)) * m + clampi(int((a + 1.0) * 0.5 * m), 0, m - 1)


# --- Making them ---------------------------------------------------------------------------

## (Worker) The lakes and rivers of `shape` (its ground as it is: no water in it yet).
## `stop` [true] (its world gone - CosmosPlanet's _exit_tree): it gives up where it is
## (checked between its stages and in its long loops: a wait on it never long).
static func make(shape: PlanetShape, stop: Array = [false]) -> PlanetWater:
	var w := PlanetWater.new()
	w.radius = shape.radius
	w._stop = stop
	if shape.sea != 1 or shape.kind != "rocky" or stop[0]:
		return w
	var t0 := Time.get_ticks_usec()
	var R := shape.radius
	var N := clampi(int(round(PI * 0.5 * R / CELL)), 24, 128)
	var NN := N * N
	var M := 6 * NN
	var csize := PI * 0.5 * R / N   # (a cell's size, m)
	var a_min := int(A_MIN_M2 / (csize * csize))
	var ka := csize * csize / 1600.0   # (what drains through a cell in 40 m cells: the widths' scale)
	var dirs := PackedVector3Array()
	dirs.resize(M)
	var raw := PackedFloat32Array()
	raw.resize(M)
	var AX := _axes()
	var town_m := PackedFloat32Array()   # (cos of a town's reach and a margin)
	for t in shape._fdir.size():
		town_m.append(cos(acos(clampf(shape._fout[t], -1.0, 1.0)) + 90.0 / R))
	# The ground: its heights (the towns' ground dear - the water kept round them).
	for f in 6:
		var A: Array = AX[f]
		for j in N:
			if stop[0]:
				return w
			for i in N:
				var d := PlanetShape.face_dir(A[0], A[1], A[2], -1.0 + (i + 0.5) * 2.0 / N, -1.0 + (j + 0.5) * 2.0 / N)
				var k := f * NN + j * N + i
				dirs[k] = d
				var h := shape.raw_height(d)
				for t in town_m.size():
					var c := d.dot(shape._fdir[t])
					var m := town_m[t]
					if c > m:
						h = maxf(h, shape._fh[t] - R) + 35.0 * smoothstep(m, shape._fout[t], c)
				raw[k] = h
	# Each cell's neighbours (8; over the faces' edges too).
	var nb := PackedInt32Array()
	nb.resize(M * 8)
	var step := 2.0 / N
	for f in 6:
		var A: Array = AX[f]
		for j in N:
			if stop[0]:
				return w
			for i in N:
				var k := f * NN + j * N + i
				var a := -1.0 + (i + 0.5) * step
				var b := -1.0 + (j + 0.5) * step
				if i > 0 and j > 0 and i < N - 1 and j < N - 1:   # (within the face: its grid's own)
					for q in 8:
						nb[k * 8 + q] = k + OFF_J[q] * N + OFF_I[q]
					continue
				for q in 8:   # (by its edge: over onto the next face)
					var o := _cell_of(PlanetShape.face_dir(A[0], A[1], A[2], a + OFF_I[q] * step, b + OFF_J[q] * step), N)
					nb[k * 8 + q] = o if o != k else -1
	# The priority flood: from the sea in, the lowest first - every cell its brim (`fill`),
	# the cell it was reached from; `order` the way they came (lowest first).
	var fill := raw.duplicate()
	var seen := PackedByteArray()
	seen.resize(M)
	var hf := PackedFloat32Array()
	var hk := PackedInt32Array()
	var order := PackedInt32Array()
	for k in M:   # (the sea: its cells by the coast the flood's start, the rest left out)
		if raw[k] < 0.0:
			seen[k] = 1
			for q in 8:
				var n := nb[k * 8 + q]
				if n >= 0 and raw[n] >= 0.0:
					_push(hf, hk, raw[k], k)
					break
	if hk.is_empty():
		return w
	while hk.size() > 0:
		if (order.size() & 511) == 0 and stop[0]:
			return w
		var c := hk[0]
		_pop(hf, hk)
		order.append(c)
		for q in 8:
			var n := nb[c * 8 + q]
			if n < 0 or seen[n]:
				continue
			seen[n] = 1
			fill[n] = maxf(raw[n], fill[c] + 0.01)
			_push(hf, hk, fill[n], n)
	if stop[0]:
		return w
	# Each land cell's water: down the steepest way (of the filled ground: always down).
	var recv := PackedInt32Array()
	recv.resize(M)
	recv.fill(-1)
	for k in M:
		if raw[k] < 0.0:
			continue
		var best := -1
		var bs := 0.0
		for q in 8:
			var n := nb[k * 8 + q]
			if n < 0:
				continue
			var dd := (dirs[n] - dirs[k]).length() * R
			var s := (fill[k] - fill[n]) / maxf(dd, 1.0)
			if s > bs:
				bs = s
				best = n
		recv[k] = best
	var acc := PackedInt32Array()
	acc.resize(M)
	acc.fill(1)
	for oi in range(order.size() - 1, -1, -1):
		var k := order[oi]
		if recv[k] >= 0:
			acc[recv[k]] += acc[k]
	if stop[0]:
		return w
	# The lakes: basins (filled over the ground: the flood's brims), above the sea, big
	# enough - each the basin's own cells (its shape), the biggest first.
	var lake_of := PackedInt32Array()
	lake_of.resize(M)
	lake_of.fill(-1)
	var comp := PackedInt32Array()
	comp.resize(M)
	comp.fill(-1)
	var cand: Array = []
	for k in M:
		if comp[k] >= 0 or raw[k] < 0.0 or fill[k] - raw[k] < 1.5:
			continue
		var cells := PackedInt32Array([k])
		comp[k] = cand.size()
		var qi := 0
		while qi < cells.size():
			var c := cells[qi]
			qi += 1
			for q in 8:
				var n := nb[c * 8 + q]
				if n >= 0 and comp[n] < 0 and raw[n] >= 0.0 and fill[n] - raw[n] > 0.05:
					comp[n] = cand.size()
					cells.append(n)
		cand.append(cells)
	cand.sort_custom(func(x, y): return x.size() > y.size())
	for cells: PackedInt32Array in cand:
		if cells.size() < LAKE_MIN or w.lakes.size() >= LAKES_MAX:
			continue
		var c := Vector3.ZERO
		var lv := -INF
		var deep := 0.0
		for k in cells:
			c += dirs[k]
			lv = maxf(lv, fill[k])
			deep = maxf(deep, fill[k] - raw[k])
		c = c.normalized()
		if lv < 2.0:
			continue
		var ok := true
		for t in shape._fdir.size():   # (none in a town)
			for k in cells:
				if dirs[k].dot(shape._fdir[t]) > cos(acos(clampf(shape._fout[t], -1.0, 1.0)) + csize * 2.0 / R):
					ok = false
					break
		if not ok:
			continue
		var li := w.lakes.size()
		var reach := 0.0
		for k in cells:
			reach = maxf(reach, (dirs[k] - c).length() * R)
			lake_of[k] = li
		w.lakes.append({"dir": c, "level": lv, "depth": clampf(deep * 0.8 + sqrt(cells.size()) * 0.9, 2.5, 16.0),
			"cells": cells.size(), "area": cells.size() * csize * csize, "reach": reach + csize * 2.5, "bmax": 1.0})
	w._lakes_pack(dirs, lake_of, nb, csize)
	if stop[0]:
		return w
	# The rivers: from each mouth (a river cell draining into the sea or a lake) up, the
	# biggest branch on as the river, the others its tributaries.
	var river := PackedByteArray()
	river.resize(M)
	for k in M:
		river[k] = 1 if raw[k] >= 0.0 and acc[k] >= a_min and lake_of[k] < 0 else 0
	var donors := {}
	for k in M:
		if river[k] and recv[k] >= 0:
			var r := recv[k]
			var l: Array = donors.get(r, [])
			l.append(k)
			donors[r] = l
	var lakes_in := {}   # (the cell a lake spills into -> [the lake, its cell it spills from])
	for k in M:
		if lake_of[k] >= 0 and recv[k] >= 0 and lake_of[recv[k]] < 0:
			lakes_in[recv[k]] = [lake_of[k], k]
	var starts: Array = []   # [cell, into, joint (planet-local, or ZERO), parent river (or -1)]
	for k in M:
		if not river[k]:
			continue
		var r := recv[k]
		if r < 0 or raw[r] < 0.0:
			starts.append([k, "sea", dirs[r] if r >= 0 else dirs[k], -1])
		elif lake_of[r] >= 0:
			starts.append([k, "lake", dirs[r], -1, lake_of[r]])
	starts.sort_custom(func(x, y): return acc[x[0]] > acc[y[0]])
	var paths: Array = []    # {cells (downstream), into, end dir, parent, from_lake, into_lake}
	var stack: Array = starts.duplicate()
	stack.reverse()
	while not stack.is_empty() and paths.size() < 4000:
		var st: Array = stack.pop_back()
		var cells := PackedInt32Array()
		var k: int = st[0]
		var from_lake := -1
		var lake_cell := -1
		while true:
			cells.append(k)
			var ds: Array = donors.get(k, [])
			var nx := -1
			for dk in ds:
				if nx < 0 or acc[dk] > acc[nx]:
					nx = dk
			for dk in ds:
				if dk != nx:
					stack.append([dk, "river", dirs[k], paths.size()])
			if lakes_in.has(k) and (nx < 0 or acc[nx] * 2 < acc[k]):
				from_lake = int(lakes_in[k][0])
				lake_cell = int(lakes_in[k][1])
				break
			if nx < 0:
				break
			k = nx
		cells.reverse()
		if lake_cell >= 0:
			cells.insert(0, lake_cell)
		paths.append({"cells": cells, "into": st[1], "end": st[2], "parent": st[3], "from_lake": from_lake,
			"into_lake": int(st[4]) if st.size() > 4 else -1})
	# Each traced as a river: smoothed, meandering, a point every STEP m; its water stepping down.
	var mean := FastNoiseLite.new()
	mean.seed = int(shape._valley.seed) + 401
	mean.frequency = 1.0 / 260.0
	mean.fractal_octaves = 2
	var kept := {}   # path index -> river index
	var by_size := range(paths.size())
	by_size.sort_custom(func(x, y):   # (the biggest first: a river always before its tributaries)
		var cx: PackedInt32Array = paths[x]["cells"]
		var cy: PackedInt32Array = paths[y]["cells"]
		return acc[cx[cx.size() - 1]] > acc[cy[cy.size() - 1]])
	for pi: int in by_size:
		if stop[0]:
			return w
		var P: Dictionary = paths[pi]
		var cells: PackedInt32Array = P["cells"]
		var parent := int(P["parent"])
		if parent >= 0 and not kept.has(parent):
			continue   # (its river dropped: so is it)
		if cells.size() < (3 if parent < 0 else 4) and int(P["from_lake"]) < 0:
			continue
		if w.rivers.size() >= RIVERS_MAX:
			break
		var line := PackedVector3Array()
		var accs := PackedFloat32Array()
		for c in cells:
			line.append(dirs[c] * R)
			accs.append(float(acc[c]) * ka)
		var end: Vector3 = P["end"]
		line.append(end * R)
		accs.append(accs[accs.size() - 1])
		var ri := w._trace(shape, line, accs, P, kept, mean)
		if ri >= 0:
			kept[pi] = ri
	w._hash_build()
	if stop[0]:
		return w
	w.stats = {"rivers": w.rivers.size(), "lakes": w.lakes.size(), "points": w.pts.size(), "grid": N, "ms": (Time.get_ticks_usec() - t0) / 1000.0,
		"length_m": 0.0, "longest_m": 0.0, "rapids_m": 0.0, "fastest": 0.0}
	for r in w.rivers:
		w.stats["length_m"] += float(r["length"])
		w.stats["longest_m"] = maxf(w.stats["longest_m"], float(r["length"]))
		w.stats["rapids_m"] += float(r["rapids"])
	for s in w.spd:
		w.stats["fastest"] = maxf(w.stats["fastest"], s)
	return w


## The grid cell of a unit direction (N a face side).
static func _cell_of(d: Vector3, N: int) -> int:
	var f := _face(d)
	var A: Array = _axes()[f]
	var dn := d.dot(A[0])
	var a := atan(d.dot(A[1]) / dn) * 4.0 / PI
	var b := atan(d.dot(A[2]) / dn) * 4.0 / PI
	var i := clampi(int((a + 1.0) * 0.5 * N), 0, N - 1)
	var j := clampi(int((b + 1.0) * 0.5 * N), 0, N - 1)
	return f * N * N + j * N + i


## A river along `line` (planet-local metres, downstream; `accs` what drains through each):
## smoothed, meandering, resampled; its water, width, depth, current. Its index, or -1.
func _trace(shape: PlanetShape, line: PackedVector3Array, accs: PackedFloat32Array, P: Dictionary, kept: Dictionary, mean: FastNoiseLite) -> int:
	var R := radius
	# (smoothed: Chaikin, the ends kept)
	for it in 3:
		var nl := PackedVector3Array([line[0]])
		var na := PackedFloat32Array([accs[0]])
		for i in line.size() - 1:
			nl.append(line[i].lerp(line[i + 1], 0.25))
			nl.append(line[i].lerp(line[i + 1], 0.75))
			na.append(lerpf(accs[i], accs[i + 1], 0.25))
			na.append(lerpf(accs[i], accs[i + 1], 0.75))
		nl.append(line[line.size() - 1])
		na.append(accs[accs.size() - 1])
		line = nl
		accs = na
	# (resampled every STEP m - and wandering side to side, not at its ends)
	var cum := PackedFloat32Array([0.0])
	for i in range(1, line.size()):
		cum.append(cum[i - 1] + line[i].distance_to(line[i - 1]))
	var L := cum[cum.size() - 1]
	if L < STEP * 4.0:
		return -1
	var n := maxi(4, int(L / STEP))
	var out := PackedVector3Array()
	var oa := PackedFloat32Array()
	var j := 0
	for s in n + 1:
		var at := L * s / n
		while j < cum.size() - 2 and cum[j + 1] < at:
			j += 1
		var t := clampf((at - cum[j]) / maxf(cum[j + 1] - cum[j], 0.001), 0.0, 1.0)
		var p := line[j].lerp(line[j + 1], t)
		var fw := (line[j + 1] - line[j]).normalized()
		var u := p.normalized()
		var side := fw.cross(u).normalized()
		var taper := smoothstep(0.0, 60.0, at) * smoothstep(0.0, 60.0, L - at)
		p += side * mean.get_noise_3dv(p) * CELL * 0.55 * taper
		out.append(p.normalized() * R)
		oa.append(lerpf(accs[j], accs[j + 1], t))
	# The ground along it; the water stepping down from the spring (the lowest yet).
	var g := PackedFloat32Array()
	for p in out:
		g.append(shape.height(p / R))
	var start := g[0] - FREEBOARD
	var from_lake := int(P["from_lake"])
	if from_lake >= 0:
		start = float(lakes[from_lake]["level"])
	var floor_lv := 0.0
	match str(P["into"]):
		"lake":
			floor_lv = float(lakes[int(P["into_lake"])]["level"])
		"river":
			var pr: Dictionary = rivers[int(kept[int(P["parent"])])]
			var e: Vector3 = (P["end"] as Vector3) * R
			var bi := int(pr["first"])
			var bd := INF
			for q in range(int(pr["first"]), int(pr["first"]) + int(pr["count"])):
				var dd := pts[q].distance_squared_to(e)
				if dd < bd:
					bd = dd
					bi = q
			floor_lv = lvl[bi]
			out[out.size() - 1] = pts[bi]
	var s_ := PackedFloat32Array()
	s_.resize(out.size())
	var cur := start
	for i in out.size():
		if from_lake < 0 or i > 2:
			cur = minf(cur, g[i] - FREEBOARD)
		s_[i] = maxf(cur, floor_lv)
	# (smoothed a little - no steps a point wide - and still never rising)
	var sm := s_.duplicate()
	for i in out.size():
		var a := 0.0
		var wsum := 0.0
		for o in range(-3, 4):
			var q := clampi(i + o, 0, out.size() - 1)
			a += s_[q]
			wsum += 1.0
		sm[i] = a / wsum
	for i in range(1, out.size()):
		sm[i] = maxf(minf(sm[i], sm[i - 1]), floor_lv)
	if from_lake >= 0:
		sm[0] = start
	# Its width, depth (shallow riffles now and then: fords), current (by the water's fall).
	var ri := rivers.size()
	var first := pts.size()
	var rapid_m := 0.0
	var riff := FastNoiseLite.new()
	riff.seed = ri * 31 + 7
	riff.frequency = 1.0 / 140.0
	for i in out.size():
		var a := oa[i]
		var w := clampf(1.3 + 0.3 * sqrt(a), 2.2, 15.0)
		var d := clampf(0.45 + 0.05 * sqrt(a), 0.65, 2.8)
		var i0 := maxi(i - 3, 0)
		var i1 := mini(i + 3, out.size() - 1)
		var slope := (sm[i0] - sm[i1]) / maxf((i1 - i0) * L / n, 1.0)
		var v := clampf(0.3 + 21.0 * slope, 0.25, 4.6)
		var rk := smoothstep(RAPID_SPEED - 0.4, RAPID_SPEED + 0.6, v)
		w *= lerpf(1.0, 0.8, rk)
		d *= lerpf(1.0, 0.8, rk)
		var rf := smoothstep(0.35, 0.6, riff.get_noise_1d(i * L / n)) * (1.0 - rk)
		d = lerpf(d, minf(d * 0.45, FORD - 0.2), rf)   # (a riffle: a ford, wadeable - the roads cross there)
		if v > RAPID_SPEED:
			rapid_m += L / n
		pts.append(out[i])
		lvl.append(sm[i])
		hw.append(w)
		dep.append(d)
		spd.append(v)
		along.append(i * L / n)
		rid.append(ri)
	rivers.append({"first": first, "count": out.size(), "length": L, "into": str(P["into"]), "from_lake": from_lake,
		"rapids": rapid_m, "drop": sm[0] - sm[sm.size() - 1], "parent": int(kept[int(P["parent"])]) if int(P["parent"]) >= 0 else -1})
	return ri


func _lakes_pack(dirs: PackedVector3Array, lake_of: PackedInt32Array, nb: PackedInt32Array, csize: float) -> void:
	_lc_size = csize
	_shore_n.seed = int(radius * 13.0) + lakes.size() * 7
	_shore_n.frequency = 1.0 / 34.0
	_shore_n.fractal_octaves = 2
	for L in lakes:
		_lk_level.append(float(L["level"]))
		_lk_depth.append(float(L["depth"]))
	_lk_bmax.resize(lakes.size())
	if lakes.is_empty():
		return
	# (each lake cell's distance in from the shore, in cells: a flood from its edge)
	var b := {}
	var front: Array = []
	for k in lake_of.size():
		if lake_of[k] < 0:
			continue
		for q in 8:
			var n := nb[k * 8 + q]
			if n >= 0 and lake_of[n] != lake_of[k]:
				b[k] = 1.0
				front.append(k)
				break
	var fi := 0
	while fi < front.size():
		var k: int = front[fi]
		fi += 1
		for q in 8:
			var n := nb[k * 8 + q]
			if n >= 0 and lake_of[n] == lake_of[k] and not b.has(n):
				b[n] = float(b[k]) + 1.0
				front.append(n)
	# (and the land round each, two rings)
	var ring := {}
	for k in b:
		for q in 8:
			var n := nb[k * 8 + q]
			if n < 0 or lake_of[n] >= 0:
				continue
			ring[n] = true
			for q2 in 8:
				var n2 := nb[n * 8 + q2]
				if n2 >= 0 and lake_of[n2] < 0:
					ring[n2] = true
	for k in b:
		_lc_p.append(dirs[k] * radius)
		_lc_l.append(lake_of[k])
		_lc_b.append(float(b[k]))
		_lk_bmax[lake_of[k]] = maxf(_lk_bmax[lake_of[k]], float(b[k]))
	for k in ring:
		_lc_p.append(dirs[k] * radius)
		_lc_l.append(-1)
		_lc_b.append(0.0)
	for i in lakes.size():
		lakes[i]["bmax"] = _lk_bmax[i]
	_lhm = maxi(8, int(2.0 * radius / HCELL))
	var tmp := {}
	for i in _lc_p.size():
		if (i & 127) == 0 and _stop[0]:
			return
		_spread(tmp, _lc_p[i], csize * 1.6, i, _lhm)
	for key in tmp:
		_lc_hash[key] = PackedInt32Array(tmp[key])


func _lkey(d: Vector3) -> int:
	return _qkey(d, _lhm)


## The lakes' field at `d`: x how much it's a lake's (0 the land, 1 well out in it; its
## shore at 0.5, wandering), y how far in (cells from the shore), z the lake (-1 none).
func _lake_field(d: Vector3, key := -1) -> Vector3:
	if _lc_hash.is_empty():
		return Vector3(0.0, 0.0, -1.0)
	var l = _lc_hash.get(_lkey(d) if key < 0 else key)
	if l == null:
		return Vector3(0.0, 0.0, -1.0)
	var p := d * radius
	var r2 := _lc_size * 1.6
	var sw := 0.0
	var sl := 0.0
	var sj := 0.0
	var lake := -1
	var bk := 0.0
	for i: int in l:
		var x := p.distance_to(_lc_p[i]) / r2
		if x >= 1.0:
			continue
		var k := (1.0 - x * x)
		k *= k
		sw += k
		if _lc_l[i] >= 0:
			sl += k
			sj += k * _lc_b[i]
			if k > bk:
				bk = k
				lake = _lc_l[i]
	if lake < 0 or sw <= 0.0:
		return Vector3(0.0, 0.0, -1.0)
	var m := sl / sw + _shore_n.get_noise_3dv(p) * 0.13
	return Vector3(m, sj / maxf(sl, 1e-6), lake)


## Lake `li`'s ground at `d` (`h` the land's; `m`, `J` its field there): its bowl down from
## its shore, a lip round it over its water (its surface's edge hidden under it), the land.
func _lake_ground(li: int, m: float, J: float, h: float) -> float:
	var L := _lk_level[li]
	var deep := _lk_depth[li] * (0.3 + 0.7 * smoothstep(1.0, maxf(2.0, _lk_bmax[li]), J))
	var T := L + LIP * smoothstep(0.5, 0.3, m) - deep * smoothstep(0.5, 0.85, m)
	var g := lerpf(maxf(h, T), minf(h, T), smoothstep(0.42, 0.56, m))
	return lerpf(h, g, smoothstep(0.08, 0.3, m))


## How much `d` is lake `li`'s (0 .. 1, 0.5 its shore) - the lake meshes' (CosmosWaters).
func lake_mask(d: Vector3, li: int) -> float:
	var f := _lake_field(d)
	return f.x if int(f.z) == li else 0.0


## The points' hash: each point in every cell within its reach (water, banks) - looked
## round it on a grid finer than the cells (whichever faces that's on).
func _hash_build() -> void:
	_hm = maxi(8, int(2.0 * radius / HCELL))
	_reach.resize(pts.size())
	var tmp := {}
	for i in pts.size():
		if (i & 127) == 0 and _stop[0]:
			return
		var reach := hw[i] + BANK_MAX + STEP * 0.6 + 2.0
		_reach[i] = reach
		_spread(tmp, pts[i], reach, i, _hm)
	for key in tmp:
		_hash[key] = PackedInt32Array(tmp[key])


## Item `i` (at planet-local `p`) put in every hash cell (`m` a face side) within `reach` m of it.
func _spread(tmp: Dictionary, p: Vector3, reach: float, i: int, m: int) -> void:
	var d := p / radius
	var c := _qcoord(d)
	var a := c.y
	var b := c.z
	var da := reach / radius * (1.0 + a * a + b * b) * 1.1
	var db := da
	if absf(a) + da < 1.0 and absf(b) + db < 1.0:   # (within its face: the cells' range)
		var f := int(c.x)
		var i0 := clampi(int((a - da + 1.0) * 0.5 * m), 0, m - 1)
		var i1 := clampi(int((a + da + 1.0) * 0.5 * m), 0, m - 1)
		var j0 := clampi(int((b - db + 1.0) * 0.5 * m), 0, m - 1)
		var j1 := clampi(int((b + db + 1.0) * 0.5 * m), 0, m - 1)
		for jj in range(j0, j1 + 1):
			for ii in range(i0, i1 + 1):
				_add(tmp, (f * m + jj) * m + ii, i)
		return
	# (by a face's edge: looked round on a fine grid, whichever faces that's on)
	var t1 := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
	var t2 := d.cross(t1)
	var cell := 2.0 * radius / m
	var k := ceili((reach + cell) / (cell * 0.45))
	var sp := (reach + cell) / k
	var seen := {}
	for x in range(-k, k + 1):
		for y in range(-k, k + 1):
			if x * x + y * y > k * k:
				continue
			var key := _qkey((p + (t1 * x + t2 * y) * sp).normalized(), m)
			if not seen.has(key):
				seen[key] = true
				_add(tmp, key, i)


## A unit direction's face and its place on it (as _qkey: f, a, b in -1 .. 1).
static func _qcoord(d: Vector3) -> Vector3:
	var ax := absf(d.x)
	var ay := absf(d.y)
	var az := absf(d.z)
	if ax >= ay and ax >= az:
		return Vector3(0.0 if d.x > 0.0 else 1.0, d.y / ax, d.z / ax)
	if ay >= az:
		return Vector3(2.0 if d.y > 0.0 else 3.0, d.x / ay, d.z / ay)
	return Vector3(4.0 if d.z > 0.0 else 5.0, d.x / az, d.y / az)


static func _add(tmp: Dictionary, key: int, i: int) -> void:
	var l = tmp.get(key)
	if l == null:
		tmp[key] = [i]
	else:
		(l as Array).append(i)


static func _push(hf: PackedFloat32Array, hk: PackedInt32Array, f: float, k: int) -> void:
	hf.append(f)
	hk.append(k)
	var i := hf.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if hf[p] <= f:
			break
		hf[i] = hf[p]
		hk[i] = hk[p]
		i = p
	hf[i] = f
	hk[i] = k


static func _pop(hf: PackedFloat32Array, hk: PackedInt32Array) -> void:
	var n := hf.size() - 1
	var lf := hf[n]
	var lk := hk[n]
	hf.resize(n)
	hk.resize(n)
	if n == 0:
		return
	var i := 0
	while true:
		var c := i * 2 + 1
		if c >= n:
			break
		if c + 1 < n and hf[c + 1] < hf[c]:
			c += 1
		if hf[c] >= lf:
			break
		hf[i] = hf[c]
		hk[i] = hk[c]
		i = c
	hf[i] = lf
	hk[i] = lk


# --- Reading them ----------------------------------------------------------------------------

## The nearest river points to `p` (planet-local metres, at the radius): the nearest
## point of each river near (up to 3) - [point index, distance^2] pairs, flat.
func _near(d: Vector3, p: Vector3, key := -1) -> PackedFloat32Array:
	var l = _hash.get(_key(d) if key < 0 else key)
	var out := PackedFloat32Array()
	if l == null:
		return out
	var best_r := PackedInt32Array()
	for i: int in l:
		var dd := p.distance_squared_to(pts[i])
		var r := rid[i]
		var found := false
		for q in best_r.size():
			if best_r[q] == r:
				found = true
				if dd < out[q * 2 + 1]:
					out[q * 2] = i
					out[q * 2 + 1] = dd
				break
		if not found:
			best_r.append(r)
			out.append(i)
			out.append(dd)
	return out


## The closest point to `p` on the river segments either side of point `i`:
## [t along it (0 .. 1 from the lower index), index of its first point, distance].
func _seg(i: int, p: Vector3) -> Vector3:
	var best := Vector3(0.0, i, INF)
	var r := rid[i]
	for a in [i - 1, i]:
		if a < 0 or a + 1 >= pts.size() or rid[a] != r or rid[a + 1] != r:
			continue
		var pa := pts[a]
		var ab := pts[a + 1] - pa
		var t := clampf((p - pa).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		var dist := p.distance_to(pa + ab * t)
		if dist < best.z:
			best = Vector3(t, a, dist)
	return best


## The ground's height at `d` (m above the radius; `h` as it was) with the lakes' bowls
## and the rivers' beds cut into it.
func carve(d: Vector3, h: float) -> float:
	if pts.is_empty() and _lc_hash.is_empty():
		return h
	var key := _qkey(d, _hm)   # (both hashes: the same cells)
	if not _lc_hash.is_empty():
		var lf := _lake_field(d, key)
		if lf.z >= 0.0 and lf.x > 0.08:
			h = _lake_ground(int(lf.z), lf.x, lf.y, h)
	if pts.is_empty():
		return h
	var p := d * radius
	var nr := _near(d, p, key)
	if nr.is_empty():
		return h
	var out := INF
	var touched := false
	for q in range(0, nr.size(), 2):
		var i := int(nr[q])
		if nr[q + 1] > _reach[i] * _reach[i]:
			continue
		var sg := _seg(i, p)
		var a := int(sg.y)
		var b := mini(a + 1, pts.size() - 1)
		var t := sg.x
		var w := lerpf(hw[a], hw[b], t)
		var s := lerpf(lvl[a], lvl[b], t)
		var dp := lerpf(dep[a], dep[b], t)
		var bank := minf(4.5 + w * 0.8 + maxf(h - s, 0.0) * 0.9, BANK_MAX)
		var x := sg.z / w
		if x > 1.0 + bank / w:
			continue
		touched = true
		var v: float
		if x < 1.0:   # (the channel: down to its bed - deeper pools left as they are)
			v = minf(h, s + LIP - (dp + LIP) * smoothstep(1.0, 0.2, x))
		else:         # (its banks: shelving up to the land - raised to just over the water where it's lower, not out in a lake or the sea)
			var tb := lerpf(s + LIP, h, smoothstep(1.0, 1.0 + bank / w, x))
			v = tb if h > tb else lerpf(tb, h, smoothstep(s - 0.2, s - 1.5, h))
		out = minf(out, v)
	return out if touched else h


## The water's surface at `d` (m above the radius) where a lake or a river is
## (the ground may still be over it - a lake's lip), else -INF. `wet_x`: how far
## across a river still counts (1 its banks' foot).
func level(d: Vector3, wet_x := 0.95) -> float:
	var best := -INF
	var lf := _lake_field(d)
	if lf.z >= 0.0 and lf.x > 0.3:
		best = _lk_level[int(lf.z)]
	if pts.is_empty():
		return best
	var p := d * radius
	var nr := _near(d, p)
	for q in range(0, nr.size(), 2):
		var i := int(nr[q])
		if nr[q + 1] > (hw[i] + STEP) * (hw[i] + STEP):
			continue
		var sg := _seg(i, p)
		var a := int(sg.y)
		var b := mini(a + 1, pts.size() - 1)
		if sg.z < lerpf(hw[a], hw[b], sg.x) * wet_x:
			best = maxf(best, lerpf(lvl[a], lvl[b], sg.x))
	return best


## The current at `d` (m/s, planet-local, along the ground): a river's, fastest in
## its middle; a lake's slow drift round. Vector3.ZERO elsewhere.
func flow(d: Vector3) -> Vector3:
	var p := d * radius
	var best := Vector3.ZERO
	var bx := INF
	if not pts.is_empty():
		var nr := _near(d, p)
		for q in range(0, nr.size(), 2):
			var i := int(nr[q])
			if nr[q + 1] > (hw[i] + STEP) * (hw[i] + STEP):
				continue
			var sg := _seg(i, p)
			var a := int(sg.y)
			var b := mini(a + 1, pts.size() - 1)
			var x := sg.z / lerpf(hw[a], hw[b], sg.x)
			if x < 1.0 and x < bx:
				bx = x
				var way := (pts[b] - pts[a]).normalized()
				best = way * lerpf(spd[a], spd[b], sg.x) * (1.0 - 0.6 * x * x)
	if bx < INF:
		return best
	var lf := _lake_field(d)
	if lf.z >= 0.0 and lf.x > 0.45:   # (a lake's slow drift, round its middle)
		var o := p - (lakes[int(lf.z)]["dir"] as Vector3) * radius
		return d.cross(o.normalized()) * 0.08 * clampf(o.length() / 20.0, 0.0, 1.0)
	return Vector3.ZERO


## The river at `d`: {i (its first point of the segment), t, x (across: 0 its middle,
## 1 its edge), speed, rapid (0 .. 1), level, depth, way (downstream, planet-local)} - {} if none.
func river_at(d: Vector3) -> Dictionary:
	if pts.is_empty():
		return {}
	var p := d * radius
	var nr := _near(d, p)
	var out := {}
	var bx := INF
	for q in range(0, nr.size(), 2):
		var i := int(nr[q])
		if nr[q + 1] > (hw[i] + STEP) * (hw[i] + STEP):
			continue
		var sg := _seg(i, p)
		var a := int(sg.y)
		var b := mini(a + 1, pts.size() - 1)
		var x := sg.z / lerpf(hw[a], hw[b], sg.x)
		if x < 1.0 and x < bx:
			bx = x
			var v := lerpf(spd[a], spd[b], sg.x)
			out = {"i": a, "t": sg.x, "x": x, "speed": v, "rapid": smoothstep(RAPID_SPEED - 0.4, RAPID_SPEED + 0.6, v),
				"level": lerpf(lvl[a], lvl[b], sg.x), "depth": lerpf(dep[a], dep[b], sg.x), "way": (pts[b] - pts[a]).normalized(), "river": rid[a]}
	return out


## How wet the ground at `d` is (1 under the water and at its edge, fading up the banks over ~4 m).
func wet(d: Vector3) -> float:
	var best := 0.0
	var lf := _lake_field(d)
	if lf.z >= 0.0:
		best = smoothstep(0.3, 0.48, lf.x)
	if pts.is_empty() or best >= 1.0:
		return best
	var p := d * radius
	var nr := _near(d, p)
	for q in range(0, nr.size(), 2):
		var i := int(nr[q])
		if nr[q + 1] > (hw[i] + STEP + 6.0) * (hw[i] + STEP + 6.0):
			continue
		var sg := _seg(i, p)
		var a := int(sg.y)
		var b := mini(a + 1, pts.size() - 1)
		var w := lerpf(hw[a], hw[b], sg.x)
		best = maxf(best, 1.0 - smoothstep(w * 0.9, w + 4.5, sg.z))
	return best


## Whether `d` is in the water or at its very edge (no plants, rocks, sites there).
func covered(d: Vector3) -> bool:
	var lf := _lake_field(d)
	if lf.z >= 0.0 and lf.x > 0.38:
		return true
	if pts.is_empty():
		return false
	var p := d * radius
	var nr := _near(d, p)
	for q in range(0, nr.size(), 2):
		var i := int(nr[q])
		if nr[q + 1] > (hw[i] + STEP + 2.0) * (hw[i] + STEP + 2.0):
			continue
		var sg := _seg(i, p)
		var a := int(sg.y)
		if sg.z < lerpf(hw[a], hw[mini(a + 1, pts.size() - 1)], sg.x) + 1.5:
			return true
	return false


## A road at `d`: 0 dry, 1 a ford (a river shallow enough to wade), 2 deep water (a lake,
## a river's deep stretch, its rapids) - CosmosRoads keeps out of that.
func crossing(d: Vector3) -> int:
	if lake_at(d) >= 0:
		return 2
	var r := river_at(d)
	if r.is_empty():
		return 0
	return 2 if float(r["depth"]) > FORD or float(r["speed"]) > RAPID_SPEED else 1


## Fords where the roads (CosmosRoads: [{pts: unit dirs}...]) cross the rivers: the river
## there made a shallow riffle (wadeable, not rapids) for ~25 m along it - its bed
## carved that much shallower from now on. New arrays, whole (the workers reading the old
## ones keep them). The crossings (planet-local), each once.
func ford(roads: Array, stop: Array = [false]) -> PackedVector3Array:
	var out := PackedVector3Array()
	if pts.is_empty():
		return out
	var nd := dep.duplicate()
	var ns := spd.duplicate()
	var done := {}
	for rd in roads:
		if stop[0]:
			return out   # (given up: the river as it was)
		for p: Vector3 in rd["pts"]:
			if not near_water(p):
				continue
			var r := river_at(p)
			if r.is_empty():
				continue
			var i: int = r["i"]
			if not done.has(i):
				done[i] = true
				out.append(pts[i])
			for q in range(i - 3, i + 5):
				if q < 0 or q >= pts.size() or rid[q] != rid[i]:
					continue
				var k := clampf(1.6 - absf(q - i - 0.5) / 2.5, 0.0, 1.0)   # (full at the road, easing off along the river)
				nd[q] = minf(nd[q], lerpf(nd[q], FORD - 0.35, k))
				ns[q] = minf(ns[q], lerpf(ns[q], RAPID_SPEED * 0.8, k))
	dep = nd
	spd = ns
	fords = out
	return out


var fords := PackedVector3Array()   # (where the roads ford the rivers: ford())


## Whether any lake or river is near `d` (within its banks' reach: a hash lookup).
func near_water(d: Vector3) -> bool:
	if pts.is_empty() and _lc_hash.is_empty():
		return false
	var key := _qkey(d, _hm)
	return _hash.has(key) or _lc_hash.has(key)


## The lake at `d` (its index), or -1.
func lake_at(d: Vector3) -> int:
	var lf := _lake_field(d)
	return int(lf.z) if lf.z >= 0.0 and lf.x > 0.5 else -1


## The river points within `reach` m of planet-local `p`: the nearest of each river near
## ([index, distance] pairs) - the sounds', the splashes'.
func nearest_point(p: Vector3, reach: float) -> int:
	var best := -1
	var bd := reach * reach
	for i in pts.size():
		var dd := pts[i].distance_squared_to(p)
		if dd < bd:
			bd = dd
			best = i
	return best
