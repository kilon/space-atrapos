class_name TownLamps
extends Node3D
## The towns' lamps (CosmosTown) and their light by night.
## Built with the town (on its worker, into its one mesh - the building shader's
## slots): lamp posts along its streets (TownStreets) and by its gates, round
## the landing field; wall lamps by its doors; oil lamps hung in the palace's
## colonnade; braziers at the palace's gates, by the altar in its court and
## before the shrine - each empire its own way:
##   Minoa - a red column wider at the top on a plinth painted with running
##     spirals, the black cushion capital, a bronze lamp bowl - or horns of
##     consecration on it and an oil lamp hung from a bronze arm;
##   Athens - a slim white marble Doric post on a plinth with the meander, a
##     bronze tripod lamp on it;
##   Sparta - a grey limestone pillar on a crimson base, the lambda band, a
##     bronze shield hung on it, a bronze fire basket on top;
##   Mycenae - a red column on a block of cyclopean stone, gold bands, rosettes,
##     a gold bowl;
##   Ionia - a slim lapis column under gold volutes, egg and dart, a gold lantern;
##   the Cyclades - a whitewashed pillar with blue bands, a little lantern under
##     a blue dome.
## Their flames (the shader's slot FLAME: lit from within, swaying) burn by
## night and dusk only - the town's `lamp_lit` (an instance parameter on its
## meshes: 0 by day, 1 by night, from its sun's height - night_of), sunk into
## their bowls by day. Their light: the nearest POOL of them round the camera
## lit by real lights (a few OmniLight3Ds reused, no shadows, each fading in
## and out as it's handed from lamp to lamp), the rest by a glow on the ground
## under each (the town's LampPools mesh: soft discs, added on, fading out near
## the camera where the real lights take over). Indoors, in your ship or under
## the ground none (no light through the walls).
##   TownLamps.of(cosmos)            # the light pool (Cosmos makes it)
##   TownLamps.place(b, kind, emp)   # (CosmosTown._make, on its worker) -> {lamps, pools}
##   TownLamps.night_of(town)        # 0 day .. 1 night

const BRONZE := 13              # (the building shader's slots: a lamp's metal, its flame)
const FLAME := 14
const POOL := 8                 # real lights at most
const RANGE := 11.0             # m: their reach
const ENERGY := 3.0
const LIGHT_COLOR := Color(1.0, 0.66, 0.36)   # (an oil flame's: warm)
const NEAR_FAR := Vector2(24.0, 34.0)   # m: a real light fades out between these from the camera (the glows on the ground fade in)
const STEP := 19.0              # m between a street's lamps
const TICK := 0.25              # s between picks
## The lamps' metal, the empire's: [colour, roughness].
const METAL := {"minoa": [[0.66, 0.43, 0.22], 0.36], "athens": [[0.7, 0.5, 0.27], 0.34], "sparta": [[0.52, 0.34, 0.18], 0.42],
	"mycenae": [[0.95, 0.74, 0.32], 0.3], "ionia": [[0.93, 0.76, 0.38], 0.3], "cyclades": [[0.62, 0.42, 0.24], 0.38],
	"": [[0.6, 0.42, 0.24], 0.4], "pirates": [[0.32, 0.29, 0.26], 0.5], "dungeon": [[0.5, 0.36, 0.2], 0.45], "cave": [[0.5, 0.36, 0.2], 0.45]}
## Lamp kinds (a lamp's [1]): its ground glow's radius.
enum { POST, SCONCE, HANG, BRAZIER }
const GLOW_R := [7.0, 4.0, 4.5, 5.5]

const WALL_T := 0.3

static var _pool_mat: ShaderMaterial
static var test_night := -1.0   # (tests: the night forced, 0..1; < 0 the sun's)

var cosmos: Node
var focus_at := Vector3.INF     # (tests: the lamps lit round here, not the camera)
var _lights: Array = []         # [OmniLight3D, key ("" free), target energy]
var _t := 0.0


## The Cosmos's lamp light (made as its child the first time).
static func of(c: Node) -> TownLamps:
	var n := c.get_node_or_null("TownLamps") as TownLamps
	if n == null:
		n = load("res://scripts/world/life/town_lamps.gd").new()
		n.name = "TownLamps"
		n.cosmos = c
		c.add_child(n)
	return n


## How dark it is at a town: 0 the sun well up .. 1 it's set (lit from a little before sunset to a little after sunrise).
static func night_of(t: Node3D) -> float:
	if test_night >= 0.0:
		return test_night
	var pl = t.get("planet")
	if pl == null or not is_instance_valid(pl):
		return 0.0
	var e: float = t.global_basis.y.normalized().dot((pl as CosmosPlanet).sun_dir)
	return 1.0 - smoothstep(-0.07, 0.1, e)


## The ground glows' material (shared; CosmosWarm draws it at the title).
static func pool_material() -> ShaderMaterial:
	if _pool_mat == null:
		_pool_mat = ShaderMaterial.new()
		_pool_mat.shader = load("res://shaders/world/lamp_pool.gdshader")
		_pool_mat.set_shader_parameter("glow", LIGHT_COLOR)
		_pool_mat.set_shader_parameter("near_far", NEAR_FAR - Vector2(6.0, 2.0))
	return _pool_mat


# --- The light by night -------------------------------------------------------------------

func _process(delta: float) -> void:
	if cosmos == null:
		return
	_t -= delta
	if _t <= 0.0:
		_t = TICK
		_pick()
	for L in _lights:
		var o: OmniLight3D = L[0]
		if not is_instance_valid(o):
			continue
		o.light_energy = move_toward(o.light_energy, float(L[2]), delta * ENERGY * 2.5)
		var on := o.light_energy > 0.004
		if o.visible != on:
			o.visible = on
		if not on and float(L[2]) <= 0.0:
			L[1] = ""


## The nearest lamps of the towns about you (the camera; `at`: there instead) lit -
## their towns' glow set by their night.
func _pick(at := Vector3.INF) -> void:
	_lights = _lights.filter(func(L): return is_instance_valid(L[0]))   # (their world gone: gone with it)
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	var towns: Dictionary = cosmos.get("_towns") if cosmos.get("_towns") != null else {}
	if at == Vector3.INF:
		at = focus_at
	var f: Vector3 = at if at != Vector3.INF else (cam.global_position if cam else Vector3.INF)
	var dark := _shut_in()
	var cands: Array = []
	for pl in towns:
		for t in towns[pl]:
			if t == null or not is_instance_valid(t) or not t.built:
				continue
			var lit := night_of(t)
			t.set_lit(lit)
			if lit <= 0.01 or dark or f == Vector3.INF or (t.lamps as Array).is_empty():
				continue
			var lf: Vector3 = t.to_local(f)
			if absf(lf.x) > float(t.site["r"]) + NEAR_FAR.y or absf(lf.z) > float(t.site["r"]) + NEAR_FAR.y or absf(lf.y) > 80.0:
				continue
			var lamps: Array = t.lamps
			for i in lamps.size():
				var p: Vector3 = lamps[i][0]
				var d2 := p.distance_squared_to(lf)
				if d2 < NEAR_FAR.y * NEAR_FAR.y:
					cands.append([d2, t, i, lit])
	var rd = cosmos.get_node_or_null("Roads")   # (and the bridges' lamps: CosmosRoads.lamps_near - [d2, null, key, lit, where, its planet])
	if rd and rd.has_method("lamps_near") and not dark and f != Vector3.INF:
		for e in rd.lamps_near(f, NEAR_FAR.y):
			cands.append([(e[1] as Vector3).distance_squared_to(f), null, e[0], e[2], e[1], e[3]])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	cands.resize(mini(cands.size(), POOL))
	var want := {}
	for c in cands:
		want[str(c[2]) if c[1] == null else "%d:%d" % [(c[1] as Node).get_instance_id(), c[2]]] = c
	for L in _lights:   # (those lit on: their targets; the rest fade out, then free)
		var c = want.get(L[1])
		if c == null:
			L[2] = 0.0
			continue
		want.erase(L[1])
		L[2] = _energy(c)
	for k in want:
		var c: Array = want[k]
		var L = null
		for M in _lights:
			if M[1] == "" or (float(M[2]) <= 0.0 and (M[0] as OmniLight3D).light_energy < 0.05):
				L = M
				break
		if L == null:
			if _lights.size() >= POOL + 2:
				continue
			L = [_new_light(), "", 0.0]
			_lights.append(L)
		var o: OmniLight3D = L[0]
		if c[1] == null:   # (a bridge's)
			var bh = c[5]
			if bh == null or not is_instance_valid(bh):
				continue
			if o.get_parent() != bh:
				if o.get_parent():
					o.reparent(bh, false)
				else:
					(bh as Node).add_child(o)
			o.light_energy = 0.0
			o.global_position = c[4]
			L[1] = k
			L[2] = _energy(c)
			continue
		var t: CosmosTown = c[1]
		var holder: Node3D = t.planet if is_instance_valid(t.planet) else t
		if o.get_parent() != holder:
			if o.get_parent():
				o.reparent(holder, false)
			else:
				holder.add_child(o)
		o.light_energy = 0.0
		o.global_position = t.to_global(t.lamps[c[2]][2])
		L[1] = k
		L[2] = _energy(c)


func _energy(c: Array) -> float:
	var d := sqrt(float(c[0]))
	return ENERGY * float(c[3]) * (1.0 - smoothstep(NEAR_FAR.x, NEAR_FAR.y, d)) * (0.75 if c[1] != null and int((c[1] as CosmosTown).lamps[c[2]][1]) == SCONCE else 1.0)


func _new_light() -> OmniLight3D:
	var o := OmniLight3D.new()
	o.name = "TownLamp"
	o.light_color = LIGHT_COLOR
	o.light_energy = 0.0
	o.omni_range = RANGE
	o.omni_attenuation = 1.1
	o.shadow_enabled = false
	o.light_specular = 0.4
	o.visible = false
	return o


## Indoors (a town's rooms, what you've built), aboard or under the ground: no lamps' light through the walls.
func _shut_in() -> bool:
	if cosmos.get("dungeon") != null:
		return true
	var w = cosmos.get("walker")
	if w == null or not is_instance_valid(w):
		return false
	if w.get("deck") != null:
		return true
	if w.planet and cosmos.has_method("town_at"):
		var t = cosmos.town_at(w.planet, w.global_position)
		if t != null and t.indoors(t.to_local(w.global_position)):
			return true
	var bl = cosmos.get("builds")
	return bl != null and bl.has_method("indoors") and bl.indoors(w.global_position)


func lit_count() -> int:
	return _lights.filter(func(L): return is_instance_valid(L[0]) and (L[0] as OmniLight3D).visible).size()


## The lights wanted lit now: [[OmniLight3D, its target energy]].
func wanted() -> Array:
	return _lights.filter(func(L): return is_instance_valid(L[0]) and float(L[2]) > 0.0).map(func(L): return [L[0], float(L[2])])


# --- Placing them (on the town's worker) -------------------------------------------------

## The town's lamps into its builder `b` (after its buildings - they're placed
## round them): {lamps: [[flame (town-local), kind, light's place]...], pools: mesh arrays (the ground's glows)}.
static func place(b, kind: String, emp: String) -> Dictionary:
	var lay := CosmosTown.layout(kind)
	var H: float = lay["half"]
	var port: Vector3 = lay["port"]
	var P := _Placer.new(b)
	P.avoid_spots(b.spots)
	for sp in CosmosSandbox.spots():
		P.avoid_spots([port + (sp[1] as Vector3)])
	var out: Array = []
	var rng: RandomNumberGenerator = b.rng
	# Along the streets: posts every STEP m, the sides taking turns (the main ones both sides) - beside the
	# paving, never on it (a crossing street's either).
	var paved: Array = []
	for s0 in TownStreets.pieces(kind, emp):
		paved.append((s0["r"] as Rect2).grow(0.45))
	for s in TownStreets.pieces(kind, emp):
		var r: Rect2 = s["r"]
		var ax: int = s["along"]
		var L: float = r.size[ax]
		var n := maxi(1, roundi(L / STEP))
		var off: float = float(s["w"]) * 0.5 + 0.75
		for k in n:
			var t := (k + 0.5) / n
			var c := r.get_center()
			var at := Vector2(r.position.x + r.size.x * t, c.y) if ax == 0 else Vector2(c.x, r.position.y + r.size.y * t)
			var sides: Array = [-1.0, 1.0] if s["main"] else [1.0 if k % 2 == 0 else -1.0]
			for sd in sides:
				var q := at + (Vector2(0, sd * off) if ax == 0 else Vector2(sd * off, 0))
				if paved.any(func(pr: Rect2): return pr.has_point(q)):
					continue   # (on a street's paving - a crossing's: not there)
				_try_post(P, out, Vector3(q.x, 0.04, q.y), emp, rng)
	# By the gates: a post either side of each street's end.
	for g in TownStreets.gates(kind, emp):
		var at: Vector3 = g["at"] - (g["out"] as Vector3) * 1.2
		var side := Vector3(-(g["out"] as Vector3).z, 0, (g["out"] as Vector3).x)
		for sd in [-1.0, 1.0]:
			_try_post(P, out, at + side * sd * (maxf(float(g["w"]), CosmosRoads.MAIN_WIDTH) * 0.5 + 1.0) + Vector3(0, 0.04, 0), emp, rng)   # (clear of the road coming in too - it's wider)
	# Round the landing field (its three outer sides; its corners have their beacons).
	for k in 3:
		for f in [-17.0, 0.0, 17.0]:
			var q: Vector3 = [Vector3(f, 0, -35.6), Vector3(f, 0, 35.6), Vector3(35.6, 0, f)][k]
			_try_post(P, out, port + q + Vector3(0, 0.05, 0), emp, rng)
	if kind == "city":
		# The palace: oil lamps hung in its colonnade, braziers at its gates and by the altar.
		var cx := 18.0
		var cz := 12.0
		for i in 5:
			var at := Vector3(-cx + 2.6, CosmosTown.STOREY, -cz + 4.0 + i * 4.0)
			out.append([hang(b, at, emp), HANG, at - Vector3(0, 0.95, 0), Vector3(at.x, 0.08, at.z)])
		for z in [cz + 15.6, -cz - 15.6]:
			for x in [-3.8, 3.8]:
				_try_brazier(P, out, Vector3(x, 0.04, z), emp)
		for x in [-2.8, 2.8]:
			_try_brazier(P, out, Vector3(x, 0.08, 0.0), emp)
	var sh: Vector3 = lay["shrine"]
	for x in [-4.6, 4.6]:
		_try_brazier(P, out, sh + Vector3(x, 0.04, 10.6), emp)
	# By the doors: a wall lamp beside most of them (the palace's, the shrine's, the storehouse's both sides).
	for d in b.doors:
		var p: Vector3 = d[0]
		var n: Vector3 = d[1]
		var side := Vector3(-n.z, 0, n.x)
		var public := absf(p.x) < 36.0 and absf(p.z) < 28.0 and kind == "city"
		public = public or Vector2(p.x - sh.x, p.z - sh.z).length() < 14.0 or Vector2(p.x - (lay["store"] as Vector3).x, p.z - (lay["store"] as Vector3).z).length() < 14.0
		var sides: Array = [-1.0, 1.0] if public else ([1.0 if rng.randf() < 0.5 else -1.0] if rng.randf() < 0.45 else [])
		for sd in sides:
			var at: Vector3 = p + n * (WALL_T * 0.5) + side * sd * (BuildKit.DOOR_W * 0.5 + 0.5)
			var fl := sconce(b, at, n, emp)
			out.append([fl, SCONCE, fl + n * 0.35 + Vector3(0, 0.1, 0), Vector3(at.x, p.y - 0.1, at.z) + n * 1.4])
	return {"lamps": out, "pools": _pools(out)}


static func _try_post(P: _Placer, out: Array, at: Vector3, emp: String, rng: RandomNumberGenerator) -> void:
	if not P.clear_at(at, 0.75):
		return
	var b = P.b
	var hanging := emp in ["minoa", "", "pirates"] and rng.randf() < 0.4
	var fl := post(b, at, emp, 1 if hanging else 0)
	P.took(at, 0.6)
	out.append([fl, POST, fl + Vector3(0, 0.35, 0), at])


static func _try_brazier(P: _Placer, out: Array, at: Vector3, emp: String) -> void:
	if not P.clear_at(at, 0.6):
		return
	var fl := brazier(P.b, at, emp)
	P.took(at, 0.5)
	out.append([fl, BRAZIER, fl + Vector3(0, 0.55, 0), at])


## Where lamps can stand: clear of the town's solids (walls, columns, jars...), its doorways and the spots people walk to.
class _Placer:
	var b
	var _cells := {}               # Vector2i (4 m) -> [Rect2] (the solids' footprints, low ones out)
	var _spots: Array = []
	var _doors: Array = []

	func _init(builder) -> void:
		b = builder
		for s in b.solids:
			if not (s is AABB):
				continue
			var a: AABB = s
			if a.end.y < 0.2 or a.position.y > 2.4:
				continue   # (floors, roofs over your head)
			_add(Rect2(a.position.x, a.position.z, a.size.x, a.size.z))
		for d in b.doors:
			var p: Vector3 = d[0]
			_doors.append(p + (d[1] as Vector3) * 1.2)

	func _add(r: Rect2) -> void:
		for i in range(floori(r.position.x / 4.0), floori(r.end.x / 4.0) + 1):
			for j in range(floori(r.position.y / 4.0), floori(r.end.y / 4.0) + 1):
				var k := Vector2i(i, j)
				if not _cells.has(k):
					_cells[k] = []
				_cells[k].append(r)

	func avoid_spots(pts: Array) -> void:
		_spots.append_array(pts)

	func clear_at(at: Vector3, clear: float) -> bool:
		var q := Vector2(at.x, at.z)
		var k := Vector2i(floori(at.x / 4.0), floori(at.z / 4.0))
		for i in range(-1, 2):
			for j in range(-1, 2):
				for r: Rect2 in _cells.get(k + Vector2i(i, j), []):
					if r.grow(clear).has_point(q):
						return false
		for p: Vector3 in _doors:
			if Vector2(p.x, p.z).distance_to(q) < 2.2:
				return false
		for p: Vector3 in _spots:
			if Vector2(p.x, p.z).distance_to(q) < 1.4:
				return false
		return true

	func took(at: Vector3, r: float) -> void:
		_add(Rect2(at.x - r, at.z - r, r * 2.0, r * 2.0))


# --- The pieces (in the town's frame, y up) ----------------------------------------------

## A flame on `at` (its foot), `r` across, `h` high: its own vertex colours - the
## FLAME slot, how far up it each ring is (g) and its height (b): the shader
## sways it, and sinks it into its bowl by day.
static func flame(b, at: Vector3, r: float, h: float, segs := 6) -> void:
	var prof: Array = [Vector2(r * 0.8, 0.0), Vector2(r, 0.2), Vector2(r * 0.76, 0.48), Vector2(r * 0.36, 0.78), Vector2(0.0, 1.0)]
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var t := Vector2(p1.x - p0.x, (p1.y - p0.y) * h).normalized()
		var n2 := Vector2(t.y, -t.x)
		var c0 := Color(FLAME / 255.0, p0.y, h, 1.0)
		var c1 := Color(FLAME / 255.0, p1.y, h, 1.0)
		for k in segs:
			var a0 := TAU * k / segs
			var a1 := TAU * (k + 1) / segs
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			var v := [at + d0 * p0.x + Vector3(0, p0.y * h, 0), at + d1 * p0.x + Vector3(0, p0.y * h, 0),
				at + d1 * p1.x + Vector3(0, p1.y * h, 0), at + d0 * p1.x + Vector3(0, p1.y * h, 0)]
			var nn := [(d0 * n2.x + Vector3(0, n2.y, 0)).normalized(), (d1 * n2.x + Vector3(0, n2.y, 0)).normalized(),
				(d1 * n2.x + Vector3(0, n2.y, 0)).normalized(), (d0 * n2.x + Vector3(0, n2.y, 0)).normalized()]
			var base: int = b.verts.size()
			b.verts.append_array(v)
			b.norms.append_array(nn)
			b.cols.append_array([c0, c0, c1, c1])
			if ((v[1] as Vector3) - (v[0] as Vector3)).cross((v[2] as Vector3) - (v[0] as Vector3)).dot(nn[0] + nn[2]) > 0.0:
				b.idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
			else:
				b.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])


## A lamp bowl on `at` (its foot): bronze, `r` across its rim, its oil level the top - the flame on it. The flame's foot.
static func bowl(b, at: Vector3, r: float, slot := BRONZE) -> Vector3:
	b.lathe(at, [Vector2(r * 0.3, 0.0), Vector2(r * 0.7, r * 0.3), Vector2(r, r * 0.62), Vector2(r * 0.96, r * 0.7)], 8, slot, true)
	return at + Vector3(0, r * 0.7 + 0.012, 0)


## A plinth: its foot, a 0.5 m band (the empire's frieze: the FRESCO slot), a cornice.
static func _plinth(b, at: Vector3, w: float, foot: int, top: int) -> float:
	b.box(at + Vector3(-w - 0.05, 0, -w - 0.05), at + Vector3(w + 0.05, 0.22, w + 0.05), foot, false)
	b.box(at + Vector3(-w, 0.22, -w), at + Vector3(w, 0.72, w), CosmosTown.FRESCO, false)
	b.box(at + Vector3(-w - 0.04, 0.72, -w - 0.04), at + Vector3(w + 0.04, 0.82, w + 0.04), top, false)
	return 0.82


## A lamp post on `at` (its foot on the ground) in the empire's style (`variant` 1: the
## Minoans' horned post with its hanging lamp). Solid. Its flame's foot.
static func post(b, at: Vector3, emp: String, variant := 0) -> Vector3:
	var fl: Vector3
	var top := 3.1
	match emp:
		"athens":
			b.box(at + Vector3(-0.36, 0, -0.36), at + Vector3(0.36, 0.14, 0.36), CosmosTown.STONE, false)
			var y := _plinth(b, at + Vector3(0, 0.14, 0), 0.26, CosmosTown.STONE, CosmosTown.PALE) + 0.14
			b.lathe(at, [Vector2(0.13, y), Vector2(0.105, 2.72)], 10, CosmosTown.PALE, false)
			b.lathe(at, [Vector2(0.105, 2.72), Vector2(0.17, 2.84), Vector2(0.18, 2.86)], 10, CosmosTown.PALE, false)
			b.box(at + Vector3(-0.2, 2.86, -0.2), at + Vector3(0.2, 2.96, 0.2), CosmosTown.PALE, false)
			for k in 3:   # (the tripod)
				var a := TAU * k / 3.0
				b.tube([at + Vector3(cos(a) * 0.17, 2.96, sin(a) * 0.17), at + Vector3(cos(a) * 0.14, 3.2, sin(a) * 0.14), at + Vector3(cos(a) * 0.09, 3.36, sin(a) * 0.09)],
					[0.018, 0.016, 0.014], 5, BRONZE)
			fl = bowl(b, at + Vector3(0, 3.3, 0), 0.22)
			top = 3.0
		"ionia":
			b.lathe(at, [Vector2(0.34, 0.0), Vector2(0.34, 0.1), Vector2(0.28, 0.16), Vector2(0.31, 0.24), Vector2(0.26, 0.3)], 10, CosmosTown.PALE)
			b.box(at + Vector3(-0.22, 0.3, -0.22), at + Vector3(0.22, 0.8, 0.22), CosmosTown.FRESCO, false)
			b.lathe(at, [Vector2(0.13, 0.8), Vector2(0.11, 2.62)], 10, CosmosTown.RED, false)
			b.box(at + Vector3(-0.2, 2.62, -0.15), at + Vector3(0.2, 2.78, 0.15), CosmosTown.BLACK, false)
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					b.disc(at + Vector3(sx * 0.2, 2.7, sz * 0.13), Vector3(0, 0, sz), 0.08, 0.04, CosmosTown.BLACK, 8)
			b.box(at + Vector3(-0.22, 2.78, -0.18), at + Vector3(0.22, 2.86, 0.18), CosmosTown.PALE, false)
			fl = _lantern(b, at + Vector3(0, 2.86, 0), CosmosTown.BLACK, BRONZE)
			top = 3.0
		"sparta":
			b.box(at + Vector3(-0.3, 0, -0.3), at + Vector3(0.3, 0.5, 0.3), CosmosTown.RED, false)
			b.box(at + Vector3(-0.24, 0.5, -0.24), at + Vector3(0.24, 1.0, 0.24), CosmosTown.FRESCO, false)
			b.box(at + Vector3(-0.17, 1.0, -0.17), at + Vector3(0.17, 2.78, 0.17), CosmosTown.STONE, false)
			b.box(at + Vector3(-0.24, 2.78, -0.24), at + Vector3(0.24, 2.9, 0.24), CosmosTown.RED, false)
			b.disc(at + Vector3(0, 1.95, 0.17), Vector3(0, 0, 1), 0.24, 0.06, CosmosTown.TRIM, 8)   # (a bronze shield hung on it, its boss)
			b.disc(at + Vector3(0, 1.95, 0.23), Vector3(0, 0, 1), 0.07, 0.04, CosmosTown.TRIM, 6)
			for k in 4:   # (the fire basket: bronze bars round its bowl)
				var a := TAU * (k + 0.5) / 4.0
				b.tube([at + Vector3(cos(a) * 0.1, 2.9, sin(a) * 0.1), at + Vector3(cos(a) * 0.26, 3.2, sin(a) * 0.26), at + Vector3(cos(a) * 0.3, 3.42, sin(a) * 0.3)],
					[0.02, 0.02, 0.018], 5, BRONZE)
			fl = bowl(b, at + Vector3(0, 2.98, 0), 0.26)
			top = 2.9
		"mycenae":
			b.box(at + Vector3(-0.42, 0, -0.42), at + Vector3(0.42, 0.6, 0.42), CosmosTown.STONE, false)
			b.box(at + Vector3(-0.43, 0.6, -0.43), at + Vector3(0.43, 0.68, 0.43), CosmosTown.TRIM, false)
			b.box(at + Vector3(-0.3, 0.68, -0.3), at + Vector3(0.3, 1.18, 0.3), CosmosTown.FRESCO, false)
			b.box(at + Vector3(-0.32, 1.18, -0.32), at + Vector3(0.32, 1.26, 0.32), CosmosTown.TRIM, false)
			_aegean(b, at, 1.26, 2.86, 0.12, 1.3)
			fl = bowl(b, at + Vector3(0, 3.02, 0), 0.25)
			top = 3.0
		"cyclades":
			b.box(at + Vector3(-0.2, 0, -0.2), at + Vector3(0.2, 2.7, 0.2), CosmosTown.PALE, false)
			for y in [0.42, 2.32]:
				b.box(at + Vector3(-0.21, y, -0.21), at + Vector3(0.21, y + 0.16, 0.21), CosmosTown.RED, false)
			b.box(at + Vector3(-0.27, 2.7, -0.27), at + Vector3(0.27, 2.78, 0.27), CosmosTown.PALE, false)
			fl = _lantern(b, at + Vector3(0, 2.78, 0), CosmosTown.RED, CosmosTown.PALE)
			top = 2.8
		_:
			var y := _plinth(b, at, 0.27, CosmosTown.BLACK, CosmosTown.BLACK)
			if variant == 1:
				# Horns of consecration on its capital, an oil lamp hung from a bronze arm.
				_aegean(b, at, y, 3.25, 0.12, 1.35)
				_little_horns(b, at + Vector3(0, 3.35, 0))
				var arm := [at + Vector3(0, 3.0, 0.16), at + Vector3(0, 3.06, 0.45), at + Vector3(0, 3.02, 0.74)]
				b.tube(arm, [0.03, 0.026, 0.022], 6, BRONZE)
				b.box(at + Vector3(-0.012, 2.6, 0.73), at + Vector3(0.012, 3.0, 0.75), BRONZE, false)   # (its chain)
				fl = bowl(b, at + Vector3(0, 2.5, 0.74), 0.17)
				flame(b, fl, 0.065, 0.24)
				b.solids.append(AABB(at - Vector3(0.32, 0, 0.32), Vector3(0.64, 3.3, 0.64)))
				return fl
			_aegean(b, at, y, 3.0, 0.12, 1.35)
			fl = bowl(b, at + Vector3(0, 3.1, 0), 0.24)
	flame(b, fl, 0.1 if emp != "sparta" else 0.13, 0.36 if emp != "sparta" else 0.44)
	b.solids.append(AABB(at - Vector3(0.34, 0, 0.34), Vector3(0.68, top, 0.68)))
	return fl


## An Aegean column y0..y1 on `at` (the red shaft wider at the top, the black cushion capital, its block).
static func _aegean(b, at: Vector3, y0: float, y1: float, r: float, taper: float) -> void:
	var r1 := r * taper
	var cy := y1 - 0.3
	b.lathe(at, [Vector2(r, y0), Vector2(r1, cy)], 8, CosmosTown.RED, false)
	var cap: Array = [Vector2(r1, cy), Vector2(r1 * 1.25, cy + 0.03)]
	for k in 3:
		var a := PI * (0.25 + 0.5 * k / 2.0)
		cap.append(Vector2(r1 * 1.05 + r1 * 0.4 * sin(a), cy + 0.09 - 0.09 * cos(a) + 0.03))
	cap.append(Vector2(r1 * 1.1, cy + 0.2))
	b.lathe(at, cap, 8, CosmosTown.BLACK)
	b.box(at + Vector3(-r1 * 1.6, cy + 0.2, -r1 * 1.6), at + Vector3(r1 * 1.6, y1 + 0.1, r1 * 1.6), CosmosTown.BLACK, false)


## Small horns of consecration (a post's), facing along x.
static func _little_horns(b, at: Vector3) -> void:
	b.box(at + Vector3(-0.26, -0.1, -0.07), at + Vector3(0.26, 0.0, 0.07), CosmosTown.HORNS, false)
	for s in [-1.0, 1.0]:
		var pts: Array = []
		var radii: Array = []
		for k in 5:
			var q := k / 4.0
			pts.append(at + Vector3(s * (0.13 + 0.07 * q * q), 0.32 * q - 0.02, 0))
			radii.append(lerpf(0.055, 0.018, q))
		b.tube(pts, radii, 6, CosmosTown.HORNS)


## A lantern on `at`: a dish, four slim posts round its flame, a little dome on them. Its flame's foot.
static func _lantern(b, at: Vector3, roof: int, posts: int) -> Vector3:
	b.lathe(at, [Vector2(0.06, 0.0), Vector2(0.2, 0.06), Vector2(0.22, 0.1)], 8, posts, true)
	for k in 4:
		var a := TAU * (k + 0.5) / 4.0
		var p := at + Vector3(cos(a) * 0.17, 0.1, sin(a) * 0.17)
		b.box(p - Vector3(0.018, 0, 0.018), p + Vector3(0.018, 0.42, 0.018), posts, false)
	var prof: Array = [Vector2(0.27, 0.0), Vector2(0.27, 0.04)]
	for k in 4:
		var a := PI * 0.5 * (k + 1) / 4.0
		prof.append(Vector2(0.25 * cos(a), 0.04 + 0.2 * sin(a)))
	b.lathe(at + Vector3(0, 0.52, 0), prof, 8, roof, false)
	return at + Vector3(0, 0.112, 0)


## A wall lamp on the wall at `at` (its face; `y` its floor), out along `n`: a plate, a bronze arm, a bowl. Its flame's foot.
static func sconce(b, at: Vector3, n: Vector3, emp: String) -> Vector3:
	var plate: int = {"minoa": CosmosTown.RED, "athens": CosmosTown.PALE, "sparta": CosmosTown.TRIM, "mycenae": CosmosTown.TRIM,
		"ionia": CosmosTown.BLACK, "cyclades": CosmosTown.RED}.get(emp, CosmosTown.RED)
	var side := Vector3(-n.z, 0, n.x)
	var p0 := at + Vector3(0, 1.98, 0)
	var a := p0 - side * 0.1 + Vector3(0, -0.12, 0)
	var c := p0 + side * 0.1 + n * 0.05 + Vector3(0, 0.26, 0)
	b.box(a, c, plate, false)
	b.tube([p0 + n * 0.04, p0 + n * 0.22 + Vector3(0, 0.04, 0), p0 + n * 0.34 + Vector3(0, 0.16, 0)], [0.022, 0.02, 0.018], 6, BRONZE)
	var fl := bowl(b, p0 + n * 0.36 + Vector3(0, 0.16, 0), 0.12)
	flame(b, fl, 0.05, 0.2)
	return fl


## An oil lamp hung from the ceiling at `at`: its chain, a bronze bowl. Its flame's foot.
static func hang(b, at: Vector3, _emp: String) -> Vector3:
	b.box(at + Vector3(-0.012, -0.62, -0.012), at + Vector3(0.012, 0, 0.012), BRONZE, false)
	b.lathe(at + Vector3(0, -0.66, 0), [Vector2(0.0, 0.0), Vector2(0.05, 0.02), Vector2(0.08, 0.06)], 8, BRONZE, false)
	var fl := bowl(b, at + Vector3(0, -0.84, 0), 0.18)
	flame(b, fl, 0.07, 0.24)
	return fl


## A brazier on `at`, the empire's way: a bronze tripod (Athens, Ionia), a stone
## block (Sparta), a drum with a gold bowl (Mycenae), a marble pedestal (the
## Cyclades), a dark stone stand (Minoa). Solid. Its flame's foot.
static func brazier(b, at: Vector3, emp: String) -> Vector3:
	var fl: Vector3
	match emp:
		"athens", "ionia":
			for k in 3:
				var a := TAU * k / 3.0
				b.tube([at + Vector3(cos(a) * 0.42, 0.0, sin(a) * 0.42), at + Vector3(cos(a) * 0.3, 0.55, sin(a) * 0.3), at + Vector3(cos(a) * 0.2, 0.96, sin(a) * 0.2)],
					[0.035, 0.03, 0.028], 6, BRONZE)
			fl = bowl(b, at + Vector3(0, 0.86, 0), 0.46)
		"sparta":
			b.box(at + Vector3(-0.36, 0, -0.36), at + Vector3(0.36, 0.72, 0.36), CosmosTown.STONE, false)
			b.box(at + Vector3(-0.4, 0.72, -0.4), at + Vector3(0.4, 0.8, 0.4), CosmosTown.RED, false)
			fl = bowl(b, at + Vector3(0, 0.8, 0), 0.44)
		"mycenae":
			b.lathe(at, [Vector2(0.4, 0.0), Vector2(0.4, 0.1), Vector2(0.3, 0.18), Vector2(0.3, 0.7), Vector2(0.38, 0.78)], 12, CosmosTown.STONE)
			b.lathe(at + Vector3(0, 0.7, 0), [Vector2(0.39, 0.0), Vector2(0.39, 0.08)], 12, CosmosTown.TRIM, false)
			fl = bowl(b, at + Vector3(0, 0.78, 0), 0.44)
		"cyclades":
			b.lathe(at, [Vector2(0.34, 0.0), Vector2(0.34, 0.12), Vector2(0.18, 0.22), Vector2(0.16, 0.74), Vector2(0.3, 0.84)], 12, CosmosTown.PALE)
			fl = bowl(b, at + Vector3(0, 0.84, 0), 0.42, CosmosTown.PALE)
		_:
			b.lathe(at, [Vector2(0.32, 0.0), Vector2(0.32, 0.1), Vector2(0.17, 0.2), Vector2(0.14, 0.72), Vector2(0.3, 0.84)], 12, CosmosTown.BLACK)
			fl = bowl(b, at + Vector3(0, 0.84, 0), 0.44)
	flame(b, fl, 0.2, 0.55, 8)
	b.solids.append(AABB(at - Vector3(0.45, 0, 0.45), Vector3(0.9, 1.2, 0.9)))
	return fl


## The ground's glows under the lamps: a soft disc each (its UVs -1..1 across it), one mesh's arrays.
static func _pools(lamps: Array) -> Array:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for L in lamps:
		var g: Vector3 = L[3]
		var r: float = GLOW_R[int(L[1])]
		var y := g.y + 0.06
		var base := verts.size()
		for k in 4:
			var u := Vector2(-1.0 if k == 0 or k == 3 else 1.0, -1.0 if k < 2 else 1.0)
			verts.append(Vector3(g.x + u.x * r, y, g.z + u.y * r))
			uvs.append(u)
			norms.append(Vector3.UP)
		idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if verts.is_empty():
		return []
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	return arr
