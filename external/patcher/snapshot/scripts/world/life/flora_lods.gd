class_name FloraLods
extends RefCounted
## The plants' levels of detail and their reach (CosmosFlora's meshes,
## CosmosPlanet's patches): the forests and the maquis drawn out to the
## horizon, each plant at the detail its size on screen needs.
##
## A chain of meshes a species, from every branch and leaf down to a handful
## of triangles: near (twigs and leaf cards), mid (clumps fringed with cards),
## far (coarse clumps), low (a few lobes and a trunk - made here from the far
## mesh: its leaves clustered into ellipsoids) and the impostor (three crossed
## cards and one across the top - the far mesh drawn into an atlas here, on the
## design's worker, from the side and from above). Which one draws a plant is
## chosen per plant, every frame, in the shader (flora.gdshaderinc): its
## distance over its size (`size_m`) - so a big plane tree keeps its leaves
## further than a small olive - through the bands LOD_K; next to a band's edge
## both meshes draw, each a complementary dither of the screen's pixels, so one
## melts into the next. Which plants each mesh is handed is CosmosPlanet's near
## field (gathered round the camera on a worker); the patches draw the impostors.
##
## Reach: every plant has a distance it fades out by (a dither too). Near, all
## of them; further, a share falling as 1 / distance (D0) - a forest stays a
## forest to the horizon at a fraction of the plants. The quadtree carries them:
## each patch (from level `top` down) owns the plants whose reach falls in its
## band (LEVEL_REACH x its size - beyond where its children take over, short of
## where its parent does), and hands them down - a patch's plants are its
## parent's (those on it) and its own. So a patch and its children draw the
## same plants where both could be seen: nothing appears or jumps when the
## ground refines. Coarse patches set each plant on their own (coarse) ground.
##   FloraLods.chain(sp)                       # (CosmosFlora._species) sp["lods"], "low", "h", "reach"
##   var atlas := FloraLods.bake(species)      # the impostors: {image, grid}, sp["imp"]
##   FloraLods.own(...) / inherit(...) / build(...)   # (CosmosPlanet's workers)

## Levels, their bands (distance / the plant's size): near, near thinned (its
## leaf cards dropped one by one to KEEP of them), mid, far, low, impostor - the
## thinned level's mesh what the near one has become by its end.
const LOD_K := [0.0, 2.0, 3.5, 7.0, 16.0, 34.0]
const LOD_T := 0.4             # (the blend: this many levels wide round each edge - leaf by leaf, flora.gdshaderinc)
const IMP := 5                 # (the impostor's level: LOD_K.size() - 1)
const KEEP := 0.25             # (the thinned levels: this share of the leaf cards - those ranked lowest)
const D0 := 120.0              # m: every plant drawn this near; beyond, D0 / distance of them
const TREE_REACH := 3500.0     # m: the furthest trees
const BUSH_REACH := 320.0
const OTHER_REACH := 900.0     # (crystals, fungi, cacti)
const LEVEL_REACH := 2.6       # a patch's plants reach this many of its sizes at most
const CELL := 64               # px: an impostor's view in the atlas
const COLS := 8
const REC := 15                # floats a plant record: a, b, dir xyz, h, sink, sc, turn, lean xz, squash xyz, reach
const LOW_SPRAY := 1.6         # (an ellipsoid's radii: this many of its points' spread)


static func is_stand(sp: Dictionary) -> bool:
	return not (str(sp["kind"]) in ["grass", "flower"])


## The share of plants drawn at `d` m.
static func share(d: float) -> float:
	return 1.0 if d <= D0 else D0 / d


## The continuous level at `x` = distance / size (the shader's lod_t).
static func lod_t(x: float) -> float:
	for k in range(LOD_K.size() - 1, -1, -1):
		if x >= float(LOD_K[k]):
			var w: float = (float(LOD_K[k + 1]) - float(LOD_K[k])) if k + 1 < LOD_K.size() else float(LOD_K[k])
			return k + (x - float(LOD_K[k])) / w
	return 0.0


## The distance / size at level `t` (lod_t's inverse).
static func x_of(t: float) -> float:
	var k := clampi(int(floor(t)), 0, LOD_K.size() - 1)
	var w: float = (float(LOD_K[k + 1]) - float(LOD_K[k])) if k + 1 < LOD_K.size() else float(LOD_K[k])
	return maxf(float(LOD_K[k]) + (t - k) * w, 0.0)


## The distances / size the meshes of levels lo..hi draw at, their blends either side included.
static func band_x(lo: int, hi: int) -> Vector2:
	return Vector2(0.0 if lo == 0 else x_of(lo - LOD_T * 0.5), INF if hi + 1 >= LOD_K.size() else x_of(hi + 1 + LOD_T * 0.5))


## The level drawn at `x` (no crossfade): 0 near .. 4 impostor.
static func level_at(x: float) -> int:
	return mini(int(lod_t(x)), LOD_K.size() - 1)


# --- The chain -------------------------------------------------------------------

## (Worker) A species' chain of meshes: sp["lods"] = [[arrays, lo, hi], ...] (the
## bands each draws - their COLOR.a says so to the shader), its low mesh, its
## size (m, for the bands) and how far it's seen.
static func chain(sp: Dictionary) -> void:
	var mid: Array = sp["arrays"]
	var far: Array = sp["far"]
	var has_far := not is_same(far, mid) and (far[Mesh.ARRAY_INDEX] as PackedInt32Array).size() < (mid[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
	var low := _low(far)
	var has_low := (low[Mesh.ARRAY_INDEX] as PackedInt32Array).size() < (far[Mesh.ARRAY_INDEX] as PackedInt32Array).size() * 0.8
	var out: Array = []
	# near (0) -> near thinned (1) -> mid (2) -> far (3) -> low (4); a mesh without
	# leaf cards (or a level it lacks) covers the next level too.
	var seed := hash(str(sp["design"]))
	var lv := 0
	if sp.has("near"):
		lv = _thinning(out, _ranked(sp["near"], seed), 0)
	var mhi := 2 if has_far else 3
	out.append([_band(mid, lv, mhi), lv, mhi])
	lv = mhi + 1
	if has_far:
		out.append([_band(far, lv, 3), lv, 3])
		lv = 4
	if has_low:
		out.append([_band(low, lv, 4), lv, 4])
	else:
		var last: Array = out.pop_back()
		out.append([_band(last[0], last[1], 4), last[1], 4])
	sp["lods"] = out
	sp["low"] = low
	var b := _bounds(far)
	sp["h"] = maxf(b.y, b.x * 1.4)   # (its size on screen: the larger of its height and (most of) its spread)
	var kind := str(sp["kind"])
	sp["reach"] = TREE_REACH if kind in ["tree", "spire"] else BUSH_REACH if kind == "bush" else OTHER_REACH


## A mesh and its thinned self in the chain from level `lv` (to `top` at most for
## the thinned one: level lv + 1 by default): the full mesh's cards drop out by
## rank over its last level (flora.gdshaderinc), the thinned one holds the KEEP
## lowest-ranked - what the full one has become by then. No cards: one mesh for
## both levels. Returns the next level.
static func _thinning(out: Array, arr: Array, lv: int, top := -1) -> int:
	var hi := lv + 1 if top < 0 else top
	var thin := _thinned(arr)
	if thin.is_empty():
		out.append([_band(arr, lv, hi), lv, hi])
		return hi + 1
	var full_hi := hi - 1
	out.append([_band(arr, lv, full_hi, true), lv, full_hi])
	out.append([_band(thin, full_hi + 1, hi), full_hi + 1, hi])
	return hi + 1


## The leaf cards (4 vertices each, UV2.x > 2.5 - CosmosFlora.M.card) ranked at
## random (seeded): the rank in UV2.y (- 16 x floor(rank x 64), under the card's
## own code) - the shader drops the highest first.
static func _ranked(arr: Array, seed: int) -> Array:
	var o := arr.duplicate()
	var uv2: PackedVector2Array = (arr[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var i := 0
	while i < uv2.size():
		if uv2[i].x > 2.5 and uv2[i].x < 6.5 and uv2[i].y > -15.5:
			var k := floori(rng.randf() * 64.0)
			for j in 4:
				if i + j < uv2.size():
					uv2[i + j].y -= 16.0 * k
			i += 4
		else:
			i += 1
	o[Mesh.ARRAY_TEX_UV2] = uv2
	return o


## The ranked arrays with only the cards ranked under KEEP ([] : no cards in it).
static func _thinned(arr: Array) -> Array:
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var out := PackedInt32Array()
	var cards := 0
	for t in range(0, ix.size(), 3):
		var u := uv2[ix[t]]
		if u.x > 2.5 and u.x < 6.5:
			cards += 1
			if rank_of(u.y) >= KEEP:
				continue
		out.append_array([ix[t], ix[t + 1], ix[t + 2]])
	if cards == 0:
		return []
	var o := arr.duplicate()
	o[Mesh.ARRAY_INDEX] = out
	return o


## A card's rank (0..1) from its UV2.y.
static func rank_of(y: float) -> float:
	return floor((-y - 1.0) / 16.0) / 64.0


## The arrays again, COLOR.a saying the levels it draws and whether its cards thin
## out over its last: (thin x 64 + lo x 8 + hi + 0.5) / 128.
static func _band(arr: Array, lo: int, hi: int, thin := false) -> Array:
	var o := arr.duplicate()
	var c: PackedColorArray = (arr[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
	var a := ((64 if thin else 0) + lo * 8 + hi + 0.5) / 128.0
	for i in c.size():
		c[i].a = a
	o[Mesh.ARRAY_COLOR] = c
	return o


## Its spread (radius) and height.
static func _bounds(arr: Array) -> Vector2:
	var r := 0.1
	var h := 0.1
	for p: Vector3 in (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array):
		r = maxf(r, Vector2(p.x, p.z).length())
		h = maxf(h, p.y)
	return Vector2(r, h)


## The low mesh: the far mesh's leaves clustered (a few ellipsoids, each its
## leaves' colour, shaded as one crown) on a five-sided trunk. Plants without
## leaves: all of it clustered.
static func _low(far: Array) -> Array:
	var vs: PackedVector3Array = far[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = far[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = far[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = far[Mesh.ARRAY_TEX_UV2]
	var leaf := PackedInt32Array()
	var wood := PackedInt32Array()
	for i in vs.size():
		if uv2[i].x > 0.5:
			leaf.append(i)
		else:
			wood.append(i)
	var leafy := leaf.size() >= 12
	if not leafy:
		leaf = PackedInt32Array(range(vs.size()))
		wood = PackedInt32Array()
	var m := CosmosFlora.M.new()
	# (its sway: as the far mesh's - UV.y over height)
	var sy := 0.0
	var hy := 0.0
	for i in vs.size():
		sy += uv[i].y
		hy += maxf(vs[i].y, 0.0)
	m.sway = sy / hy if hy > 0.01 else 0.0
	var k := clampi(leaf.size() / 25, 3, 6)
	var km := _kmeans(vs, leaf, k)
	var cl := _clusters(vs, cs, uv, leaf, km[1], km[0])
	var crown := Vector3.ZERO
	for i in leaf:
		crown += vs[i]
	crown /= maxf(leaf.size(), 1)
	var bottom := INF
	m.leaf = 1.0 if leafy else 0.0
	var ico: Array = CosmosFlora._ico_cached(0)
	for c: Array in cl:
		var cen: Vector3 = c[0]
		var r: Vector3 = c[1]
		var col: Color = c[2]
		m.glow = c[3]
		bottom = minf(bottom, cen.y - r.y * 0.8)
		var base := m.v.size()
		for e: Vector3 in ico[0]:
			var p := cen + e * r
			var n := (e / r).normalized()
			if leafy:
				n = (n + (p - crown).normalized() * 0.7).normalized()
			m.add(p, n, col * (0.74 + 0.34 * (n.y * 0.5 + 0.5)))
		for f: Array in ico[1]:
			m.tri(base + int(f[0]), base + int(f[1]), base + int(f[2]))
	m.glow = 0.0
	if leafy and not wood.is_empty() and bottom > 0.3:
		# The trunk: from the ground to inside the crown, as thick as the far mesh's at its foot.
		var foot := 0.0
		var nf := 0
		var top := Vector2.ZERO
		var nt := 0
		var bark := Color(0, 0, 0)
		for i in wood:
			var p := vs[i]
			bark += cs[i]
			if p.y < minf(0.8, bottom * 0.3):
				foot += Vector2(p.x, p.z).length()
				nf += 1
			elif absf(p.y - bottom) < 0.8:
				top += Vector2(p.x, p.z)
				nt += 1
		bark /= wood.size()
		var r0 := clampf(foot / maxf(nf, 1) * 0.9, 0.06, 1.2)
		var tc := top / maxf(nt, 1)
		var y1 := bottom + 0.6
		m.leaf = 0.0
		var base := m.v.size()
		for ring in 2:
			for s in 5:
				var a := TAU * s / 5.0
				var dir := Vector3(cos(a), 0.0, sin(a))
				var p := dir * (r0 if ring == 0 else r0 * 0.55) + (Vector3(tc.x, y1, tc.y) if ring == 1 else Vector3.ZERO)
				m.add(p, dir, bark)
		for s in 5:
			var s1 := (s + 1) % 5
			m.quad(base + s, base + s1, base + 5 + s1, base + 5 + s)
	return m.arrays()


## Points `ids` of `vs` in `k` clusters (k-means from the farthest points - the
## same every time): [centres, each point's cluster]. _clusters: [centre, radii, colour, glow] each.
static func _kmeans(vs: PackedVector3Array, ids: PackedInt32Array, k: int) -> Array:
	var cents: Array = []
	var top := ids[0]
	for i in ids:
		if vs[i].y > vs[top].y:
			top = i
	cents.append(vs[top])
	while cents.size() < k:
		var best := ids[0]
		var bd := -1.0
		for i in ids:
			var dd := INF
			for c: Vector3 in cents:
				dd = minf(dd, vs[i].distance_squared_to(c))
			if dd > bd:
				bd = dd
				best = i
		cents.append(vs[best])
	var own := PackedInt32Array()
	own.resize(vs.size())
	for it in 6:
		var sum: Array = []
		var cnt := PackedInt32Array()
		cnt.resize(k)
		for c in k:
			sum.append(Vector3.ZERO)
		for i in ids:
			var bi := 0
			var bd := INF
			for c in k:
				var dd := vs[i].distance_squared_to(cents[c])
				if dd < bd:
					bd = dd
					bi = c
			own[i] = bi
			sum[bi] += vs[i]
			cnt[bi] += 1
		for c in k:
			if cnt[c] > 0:
				cents[c] = sum[c] / cnt[c]
	return [cents, own]


static func _clusters(vs: PackedVector3Array, cs: PackedColorArray, uv: PackedVector2Array, ids: PackedInt32Array, own: PackedInt32Array, cents: Array) -> Array:
	var out: Array = []
	for c in cents.size():
		var sq := Vector3.ZERO
		var col := Color(0, 0, 0, 0)
		var glow := 0.0
		var n := 0
		for i in ids:
			if own[i] != c:
				continue
			var d: Vector3 = vs[i] - cents[c]
			sq += d * d
			col += cs[i]
			glow += uv[i].x
			n += 1
		if n < 3:
			continue
		var r := Vector3(sqrt(sq.x / n), sqrt(sq.y / n), sqrt(sq.z / n)) * LOW_SPRAY
		col /= n
		col.a = 1.0
		out.append([cents[c], r.max(Vector3.ONE * 0.08), col, glow / n])
	return out


# --- The impostors ---------------------------------------------------------------

## (Worker) Every stand's far mesh drawn into one atlas, from the side and from
## above (CELL px each; colour and coverage, the colours bled past the edges for
## the mipmaps): {"image": Image (mipmapped), "grid": Vector2(cols, rows)}; each
## stand's sp["imp"] = Vector4(atlas index, width, height, the top card's height / height).
## `stop` [true]: given up ({}).
static func bake(flora: Array, stop: Array = []) -> Dictionary:
	var stands: Array = []
	for sp: Dictionary in flora:
		if is_stand(sp):
			stands.append(sp)
	var cells := maxi(stands.size() * 2, 1)
	var rows := ceili(cells / float(COLS))
	var w := COLS * CELL
	var data := PackedByteArray()
	data.resize(w * rows * CELL * 4)
	for i in stands.size():
		if not stop.is_empty() and stop[0]:
			return {}   # (its world gone meanwhile)
		var sp: Dictionary = stands[i]
		var far: Array = sp["far"]
		var b := _bounds(far)
		var r := b.x * 1.02
		var h := b.y * 1.02
		var vs: PackedVector3Array = far[Mesh.ARRAY_VERTEX]
		var uv2: PackedVector2Array = far[Mesh.ARRAY_TEX_UV2]
		var ly := 0.0
		var nl := 0
		for j in vs.size():
			if uv2[j].x > 0.5:
				ly += vs[j].y
				nl += 1
		var topk := clampf((ly / nl) / h if nl > 0 else 0.6, 0.2, 0.9)
		for view in 2:
			var cell := i * 2 + view
			_raster(far, view, r, h, data, w, (cell % COLS) * CELL, (cell / COLS) * CELL, stop)
			if not stop.is_empty() and stop[0]:
				return {}
		sp["imp"] = Vector4(i, r * 2.0, h, topk)
	var img := Image.create_from_data(w, rows * CELL, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return {"image": img, "grid": Vector2(COLS, rows)}


## One view of a mesh into the atlas at (ox, oy): 0 from the side (x across, y
## up, nearest +z), 1 from above (x, z; highest y) - each triangle its vertices'
## mean colour; then the colours bled two pixels out (coverage 0 there).
static func _raster(arr: Array, view: int, r: float, h: float, data: PackedByteArray, w: int, ox: int, oy: int, stop: Array = []) -> void:
	var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cs: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var N := CELL
	var px := PackedVector3Array()   # (pixel x, pixel y, depth)
	px.resize(vs.size())
	for i in vs.size():
		var p := vs[i]
		if view == 0:
			px[i] = Vector3((p.x + r) / (2.0 * r) * N, (h - p.y) / h * N, p.z)
		else:
			px[i] = Vector3((p.x + r) / (2.0 * r) * N, (p.z + r) / (2.0 * r) * N, p.y)
	var zb := PackedFloat32Array()
	zb.resize(N * N)
	zb.fill(-INF)
	var col := PackedColorArray()
	col.resize(N * N)
	for t in range(0, ix.size(), 3):
		if t % 1500 == 0 and not stop.is_empty() and stop[0]:
			return   # (its world gone: stop mid-way)
		var a := px[ix[t]]
		var b := px[ix[t + 1]]
		var c := px[ix[t + 2]]
		var area := (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
		if absf(area) < 1e-6:
			continue
		var tc := (cs[ix[t]] + cs[ix[t + 1]] + cs[ix[t + 2]]) / 3.0
		var x0 := maxi(int(floor(minf(a.x, minf(b.x, c.x)))), 0)
		var x1 := mini(int(ceil(maxf(a.x, maxf(b.x, c.x)))), N - 1)
		var y0 := maxi(int(floor(minf(a.y, minf(b.y, c.y)))), 0)
		var y1 := mini(int(ceil(maxf(a.y, maxf(b.y, c.y)))), N - 1)
		var inv := 1.0 / area
		for y in range(y0, y1 + 1):
			var fy := y + 0.5
			for x in range(x0, x1 + 1):
				var fx := x + 0.5
				var w0 := ((b.x - fx) * (c.y - fy) - (b.y - fy) * (c.x - fx)) * inv
				var w1 := ((c.x - fx) * (a.y - fy) - (c.y - fy) * (a.x - fx)) * inv
				var w2 := 1.0 - w0 - w1
				if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
					continue
				var z := a.z * w0 + b.z * w1 + c.z * w2
				var q := y * N + x
				if z > zb[q]:
					zb[q] = z
					col[q] = tc
	var cover := PackedByteArray()
	cover.resize(N * N)
	for q in N * N:
		cover[q] = 255 if zb[q] > -INF else 0
	var filled := cover.duplicate()
	for pass_i in 2:   # (bleed the colours outward: no dark fringe in the mipmaps)
		var next := filled.duplicate()
		for y in N:
			for x in N:
				var q := y * N + x
				if filled[q] != 0:
					continue
				var s := Color(0, 0, 0, 0)
				var n := 0
				for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var xx := x + o.x
					var yy := y + o.y
					if xx >= 0 and yy >= 0 and xx < N and yy < N and filled[yy * N + xx] != 0:
						s += col[yy * N + xx]
						n += 1
				if n > 0:
					col[q] = s / n
					next[q] = 1
		filled = next
	for y in N:
		for x in N:
			var q := y * N + x
			var o := ((oy + y) * w + ox + x) * 4
			var c: Color = col[q]
			data[o] = clampi(int(c.r * 255.0), 0, 255)
			data[o + 1] = clampi(int(c.g * 255.0), 0, 255)
			data[o + 2] = clampi(int(c.b * 255.0), 0, 255)
			data[o + 3] = cover[q]


static var _imp_mesh: ArrayMesh


## The impostor: three upright cards crossed (60 degrees apart) and one across
## the top (the shader sets its height: the plant's crown) - a unit plant (1
## wide, 1 tall: its transform sizes it). UV2.x 7 + u, UV2.y -(20 + v) the side
## view, -(22 + v) the top; normals round, as a crown's.
static func impostor_arrays() -> Array:
	var m := CosmosFlora.M.new()
	m.sway = 0.0
	m.leaf = 1.0
	var a := (IMP * 8 + IMP + 0.5) / 128.0
	var col := Color(1, 1, 1, a)
	for k in 3:
		var ang := PI * k / 3.0
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var base := m.v.size()
		for q in 4:
			var u := float(q == 1 or q == 2)
			var t := float(q >= 2)
			var p := dir * (u - 0.5) + Vector3(0, t, 0)
			var n := (Vector3(p.x * 1.6, (t - 0.45) * 1.2 + 0.35, p.z * 1.6)).normalized()
			m.v.append(p)
			m.nr.append(n)
			m.c.append(col)
			m.uv.append(Vector2.ZERO)
			m.uv2.append(Vector2(7.0 + u * 0.999, -(20.0 + t * 0.999)))
		m.ix.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	var base := m.v.size()
	for q in 4:
		var u := float(q == 1 or q == 2)
		var t := float(q >= 2)
		m.v.append(Vector3(u - 0.5, 0.6, t - 0.5))
		m.nr.append(Vector3.UP)
		m.c.append(col)
		m.uv.append(Vector2.ZERO)
		m.uv2.append(Vector2(7.0 + u * 0.999, -(22.0 + t * 0.999)))
	m.ix.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	return m.arrays()


static func impostor_mesh() -> ArrayMesh:
	if _imp_mesh == null:
		_imp_mesh = ArrayMesh.new()
		_imp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, impostor_arrays())
	return _imp_mesh


# --- Their places on the patches --------------------------------------------------

## (Worker) The plants a patch owns: those whose reach falls in [lo, hi) m - k ->
## PackedFloat32Array of REC-float records. Each species its own seed (the
## patch's and its own), candidates spread over the whole patch as many as its
## density x the share of plants in that band, each kept by the woods' and its
## territories' chance and how well it grows there (CosmosFlora.cluster, site).
static func own(flora: Array, shape: PlanetShape, radius: float, seed: int, n: Vector3, u: Vector3, v: Vector3,
		a0: float, b0: float, span: float, lo: float, hi: float) -> Dictionary:
	var out := {}
	var area := pow(span * radius * 0.9, 2.0) / 100.0
	var step := 1.2 / radius
	var rng := RandomNumberGenerator.new()
	for k in flora.size():
		var sp: Dictionary = flora[k]
		if not is_stand(sp):
			continue
		var cap: float = sp.get("reach", TREE_REACH)
		var top := minf(hi, cap)
		if lo >= top:
			continue
		var f_lo := share(lo)
		var f_hi := share(top)
		if f_lo - f_hi <= 1e-6:
			continue
		rng.seed = hash([seed, k, 77])
		var cnt := int(float(sp["density"]) * area * (f_lo - f_hi) + rng.randf())
		var rec := PackedFloat32Array()
		var tilt: float = sp["tilt"]
		var small: float = float(sp["size"].x) * 0.65
		for i in cnt:
			var a := a0 + rng.randf() * span
			var b := b0 + rng.randf() * span
			var pick := rng.randf()
			var reach_v := lerpf(f_hi, f_lo, rng.randf())
			var d := PlanetShape.face_dir(n, u, v, a, b)
			var ch := CosmosFlora.cluster(sp, d, radius)
			if pick > ch:
				continue
			var h := shape.height(d)
			var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var slope := absf(shape.height((d + t * step).normalized()) - h) / 1.2
			if pick > ch * CosmosFlora.site(sp, shape, h, slope):
				continue
			var sc := CosmosFlora.size_of(sp, rng)
			var reach := clampf(D0 / maxf(reach_v, 1e-4), lo, top)
			if sc < small:
				reach = minf(reach, 70.0)   # (the saplings: only near)
			rec.append_array([a, b, d.x, d.y, d.z, h, 0.06 * sc + slope * 0.4 * sc, sc, rng.randf() * TAU,
				rng.randf_range(-1, 1) * tilt, rng.randf_range(-1, 1) * tilt,
				rng.randf_range(0.88, 1.12), rng.randf_range(0.88, 1.15), rng.randf_range(0.88, 1.12), reach])
		if not rec.is_empty():
			out[k] = rec
	return out


## The records of `all` on the square (a0, b0, span) - and `own` added.
static func inherit(all: Dictionary, a0: float, b0: float, span: float, mine: Dictionary) -> Dictionary:
	var out := {}
	for k in all:
		var src: PackedFloat32Array = all[k]
		var rec := PackedFloat32Array()
		for i in range(0, src.size(), REC):
			var a := src[i]
			var b := src[i + 1]
			if a >= a0 and a < a0 + span and b >= b0 and b < b0 + span:
				rec.append_array(src.slice(i, i + REC))
		if not rec.is_empty():
			out[k] = rec
	for k in mine:
		out[k] = (out.get(k, PackedFloat32Array()) as PackedFloat32Array) + (mine[k] as PackedFloat32Array)
	return out


## (Worker) A patch's plants as MultiMesh buffers (`bare`: PlanetShape's ground built over, a snapshot) (TRANSFORM_3D + custom: size m,
## reach, atlas index + the top card's height, glow): {k: [buffer, count, sc min, sc max,
## reach max, AABB]}, "imp": the impostors' (all species, one buffer) - and the solid
## ones' trunks [point, radius, height] in `solids`. Set on the patch's own ground
## (`hs`: its grid, PATCH + 3 a side) unless `exact` (the finest: on the true ground).
static func build(flora: Array, shape: PlanetShape, radius: float, all: Dictionary, a0: float, b0: float, span: float,
		centre: Vector3, hs: PackedFloat32Array, patch: int, exact: bool, digs: PackedFloat64Array, solids: Array, bare: Array = []) -> Dictionary:
	var out := {}
	var imp := PackedFloat32Array()
	var imp_n := 0
	var imp_box := AABB()
	var imp_lo := INF
	var imp_hi := 0.0
	var imp_r := 0.0
	var G := patch + 3
	var step := span / patch
	for k in all:
		var sp: Dictionary = flora[k]
		var src: PackedFloat32Array = all[k]
		var ih: float = sp["h"]
		var iv: Vector4 = sp.get("imp", Vector4(-1, 1, 1, 0.6))
		var solid: float = sp["solid"]
		var tall: float = sp["tall"]
		var glow: float = sp["glow"]
		var buf := PackedFloat32Array()
		var cnt := 0
		var smin := INF
		var smax := 0.0
		var rmax := 0.0
		var box := AABB()
		for i in range(0, src.size(), REC):
			var d := Vector3(src[i + 2], src[i + 3], src[i + 4])
			if shape.cleared(d) or _bare(d, bare) or shape.dug_here(d, digs):
				continue
			var h := src[i + 5]
			if not exact and not hs.is_empty():
				var fx := clampf((src[i] - a0) / step, 0.0, patch - 0.001)
				var fy := clampf((src[i + 1] - b0) / step, 0.0, patch - 0.001)
				var gx := int(fx)
				var gy := int(fy)
				fx -= gx
				fy -= gy
				var q := (gy + 1) * G + gx + 1
				var h00 := hs[q]
				var h11 := hs[q + G + 1]
				if fx > fy:   # (the terrain's own triangles: CosmosPlanet._build)
					h = h00 + fx * (hs[q + 1] - h00) + fy * (h11 - hs[q + 1])
				else:
					h = h00 + fy * (hs[q + G] - h00) + fx * (h11 - hs[q + G])
			var sc := src[i + 7]
			var t := d.cross(Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT).normalized()
			var x := t.rotated(d, src[i + 8])
			var bs := Basis(x, d, x.cross(d)) * Basis.from_euler(Vector3(src[i + 9], 0.0, src[i + 10])) \
				* Basis.from_scale(Vector3(src[i + 11], src[i + 12], src[i + 13]) * sc)
			var at := d * (radius + h - src[i + 6])
			var o := at - centre
			var reach := src[i + 14]
			var size := ih * sc
			_put(buf, bs, o, Vector4(size, reach, maxf(iv.x, 0.0) + iv.w * 0.98, glow))
			cnt += 1
			smin = minf(smin, sc)
			smax = maxf(smax, sc)
			rmax = maxf(rmax, reach)
			var ext := Vector3.ONE * size * 1.2
			var pb := AABB(o - ext, ext * 2.0)
			box = pb if cnt == 1 else box.merge(pb)
			if iv.x >= 0.0 and reach > x_of(IMP - LOD_T * 0.5) * size:
				var ib := bs * Basis.from_scale(Vector3(iv.y, iv.z, iv.y))
				_put(imp, ib, o, Vector4(size, reach, iv.x + iv.w * 0.98, glow))
				imp_box = pb if imp_n == 0 else imp_box.merge(pb)
				imp_n += 1
				imp_lo = minf(imp_lo, size)
				imp_hi = maxf(imp_hi, size)
				imp_r = maxf(imp_r, reach)
			if solid > 0.0 and solids != null and exact:
				solids.append([at, solid * sc, tall * sc])
		if cnt > 0:
			out[k] = [buf, cnt, smin, smax, rmax, box]
	if imp_n > 0:
		out["imp"] = [imp, imp_n, imp_lo, imp_hi, imp_r, imp_box]   # (sizes in m, not scales)
	return out


## Ground built over (PlanetShape.bare, from its list as the main thread had it -
## not read while it's being replaced).
static func _bare(d: Vector3, list: Array) -> bool:
	for b in list:
		if d.dot(b[0]) < b[1]:
			continue
		var dirs: PackedVector3Array = b[2]
		var coss: PackedFloat32Array = b[3]
		for i in dirs.size():
			if d.dot(dirs[i]) > coss[i]:
				return true
	return false


static func _put(b: PackedFloat32Array, bs: Basis, o: Vector3, c: Vector4) -> void:
	b.append_array([bs.x.x, bs.y.x, bs.z.x, o.x, bs.x.y, bs.y.y, bs.z.y, o.y, bs.x.z, bs.y.z, bs.z.z, o.z, c.x, c.y, c.z, c.w])


## The distance band (m) a level's meshes draw for plants of size `size` - with
## the crossfade either side: [from, to].
static func band_m(lo: int, hi: int, size_lo: float, size_hi: float) -> Vector2:
	var bx := band_x(lo, hi)
	var a: float = bx.x * size_lo
	var b: float = bx.y * size_hi
	return Vector2(a, b)
