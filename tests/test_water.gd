extends TestCase
## A sea world's lakes and rivers (PlanetWater, CosmosWaters): made from its
## ground - rivers running down to the sea or a lake, their beds below their
## banks, the same every time; nothing grows in them, the towns and roads keep
## off them (roads only through a ford); their currents carry a swimmer (in
## rapids, harder than you can swim), the underwater look in them too.

var _old_system := ""


func setup() -> void:
	_old_system = Galaxy.current_system
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""


func teardown() -> void:
	Galaxy.current_system = _old_system
	Cosmos.arrive_from = ""


func _amnissos_rec() -> Dictionary:
	for r in Cosmos.planet_records(Galaxy.HOME):
		if str(r.get("name", "")) == "Amnissos":
			return r
	return {}


## Amnissos's ground as CosmosPlanet makes it: its towns levelled first, then its water.
func _shape(rec: Dictionary) -> Array:
	var sh := PlanetShape.of(rec, false)
	var towns := CosmosTown.sites(sh, rec, Galaxy.owner_of(str(rec.get("system", Galaxy.HOME))))
	sh.set_flats(CosmosTown.flats_of(towns, sh.radius))
	sh.water = PlanetWater.make(sh)
	return [sh, towns]


func test_rivers_run_down_to_the_sea_or_a_lake() -> void:
	var rec := _amnissos_rec()
	var a := _shape(rec)
	var sh: PlanetShape = a[0]
	var w := sh.water
	check(w.rivers.size() >= 5, "Amnissos has rivers (%d, %.1f km of them)" % [w.rivers.size(), float(w.stats["length_m"]) / 1000.0])
	check(w.lakes.size() >= 2, "and lakes (%d)" % w.lakes.size())
	check(float(w.stats["rapids_m"]) > 100.0, "and rapids on the steep stretches (%.0f m)" % float(w.stats["rapids_m"]))
	var down := 0
	var ends := 0
	var beds := 0
	var bed_n := 0
	var wider := 0
	var bad: Array = []
	for ri in w.rivers.size():
		var r: Dictionary = w.rivers[ri]
		var first := int(r["first"])
		var n := int(r["count"])
		var ok := true
		for i in range(first + 1, first + n):
			if w.lvl[i] > w.lvl[i - 1] + 0.001:
				ok = false
		if ok:
			down += 1
		var last := first + n - 1
		var e := w.pts[last] / sh.radius
		match str(r["into"]):
			"sea":
				if w.lvl[last] < 1.0 and sh.height(e) < 0.6:
					ends += 1
			"lake":
				var lf := w._lake_field(e)
				if lf.z >= 0.0 and lf.x > 0.25 and w.lvl[last] >= float(w.lakes[int(lf.z)]["level"]) - 0.5:   # (into it - at its level, or a step above it where two lakes meet)
					ends += 1
			"river":
				ends += 1
		if ends != ri + 1 - bad.size():
			bad.append("%s lvl %.1f h %.1f field %s" % [r["into"], w.lvl[last], sh.height(e), w._lake_field(e)])
		if w.hw[last] >= w.hw[first]:
			wider += 1
		# (its bed under its water, its banks over it - where it runs on land)
		for i in range(first + 4, last - 4, 9):
			var d := w.pts[i] / sh.radius
			if w.lake_at(d) >= 0 or w.lvl[i] < 0.5:
				continue
			var u := w.pts[i].normalized()
			var side := (w.pts[i + 1] - w.pts[i - 1]).cross(u).normalized()
			var bank_l := sh.height((w.pts[i] + side * (w.hw[i] * 1.25 + 1.0)).normalized())
			var bank_r := sh.height((w.pts[i] - side * (w.hw[i] * 1.25 + 1.0)).normalized())
			bed_n += 1
			if sh.height(d) < w.lvl[i] - 0.25 and bank_l > w.lvl[i] and bank_r > w.lvl[i]:
				beds += 1
	check_eq(down, w.rivers.size(), "every river's water steps down its course, never up")
	check_eq(ends, w.rivers.size(), "every river ends in the sea, a lake or the river it joins %s" % str(bad))
	check(wider >= w.rivers.size() * 0.8, "wider downstream (%d of %d)" % [wider, w.rivers.size()])
	check(bed_n > 50 and beds >= bed_n * 0.9, "their beds under the water, their banks over it (%d of %d)" % [beds, bed_n])
	# A lake: its water over its floor, its shore up out of it.
	var L: Dictionary = w.lakes[0]
	var c: Vector3 = L["dir"]
	var deep := 0.0
	for k in 40:
		var d := (c * sh.radius + c.cross(Vector3.UP).normalized().rotated(c, k * 0.7) * float(k)).normalized()
		if w.lake_at(d) == 0:
			deep = maxf(deep, float(L["level"]) - sh.height(d))
	check(deep > 1.5, "the biggest lake's floor under its water (%.1f m deep)" % deep)
	check(sh.water_level(c) > -INF, "its surface known there (%.1f m up)" % sh.water_level(c))


func test_the_same_every_time() -> void:
	var rec := _amnissos_rec()
	var a: PlanetShape = _shape(rec)[0]
	var b: PlanetShape = _shape(rec)[0]
	check_eq(a.water.pts, b.water.pts, "the rivers in the same places")
	check_eq(a.water.lvl, b.water.lvl, "at the same levels")
	check_eq(a.water.lakes.size(), b.water.lakes.size(), "the same lakes")
	var d := a.water.pts[a.water.pts.size() / 2] / a.radius
	check_eq(a.height(d), b.height(d), "the same ground in their beds")


func test_nothing_grows_in_them_and_towns_keep_off() -> void:
	var rec := _amnissos_rec()
	var a := _shape(rec)
	var sh: PlanetShape = a[0]
	var towns: Array = a[1]
	var w := sh.water
	var bare := 0
	var n := 0
	for i in range(0, w.pts.size(), 5):
		var d := w.pts[i] / sh.radius
		if sh.height(d) < 0.0:
			continue
		n += 1
		if sh.cleared(d):   # (no plants, no boulders: CosmosPlanet, CosmosFlora, FloraLods all ask)
			bare += 1
	check(n > 50 and bare == n, "no plants or rocks in the rivers (%d of %d points bare)" % [bare, n])
	var lk := 0
	for li in w.lakes.size():
		if sh.cleared(w.lakes[li]["dir"]) or w.lake_at(w.lakes[li]["dir"]) != li:
			lk += 1
	check_eq(lk, w.lakes.size(), "none in the lakes")
	var near := 0
	for t in towns:
		var td: Vector3 = t["dir"]
		var r := float(t.get("r", 150.0))
		for i in w.pts.size():
			if (w.pts[i] / sh.radius).dot(td) > cos(r / sh.radius):
				near += 1
		for L in w.lakes:
			if (L["dir"] as Vector3).dot(td) > cos(r / sh.radius):
				near += 1
	check(towns.size() >= 2, "Amnissos has towns (%d)" % towns.size())
	check_eq(near, 0, "no river or lake in a town")
	# Its roads: never through deep water - over a river only at a ford (made shallow where they cross: PlanetWater.ford).
	var roads := CosmosRoads.network(sh, towns)
	w.ford(roads)
	var deep := 0
	var fords := 0
	for rd in roads:
		var pts: PackedVector3Array = rd["pts"]
		for i in pts.size():
			var c := w.crossing(pts[i])
			if c == 2:
				deep += 1
			elif c == 1:
				fords += 1
	check(not roads.is_empty(), "roads between the towns (%d)" % roads.size())
	check_eq(deep, 0, "no road through a lake or a river's deep water (%d points at fords)" % fords)


## Out from a beach: a few metres deep for the first tens of metres, then the floor dropping
## away ever steeper - tens of metres a few hundred out, deep water beyond.
func test_the_sea_floor_drops_off_from_the_shore() -> void:
	var sh := PlanetShape.of(_amnissos_rec(), false)
	var at := PackedFloat32Array()
	at.resize(5)
	var n := 0
	for k in 20000:
		var d := Vector3(sin(k * 1.7), cos(k * 2.3), sin(k * 0.9 + 1.0)).normalized()
		var h := sh.height(d)
		if h < 0.3 or h > 1.2:
			continue
		var t := d.cross(Vector3.UP).normalized()
		for q in 8:
			var f := t.rotated(d, q * TAU / 8.0)
			if sh.height((d * sh.radius + f * 30.0).normalized()) < -0.2 and sh.height((d * sh.radius + f * 400.0).normalized()) < -2.0:
				var i := 0
				for m in [40.0, 100.0, 200.0, 400.0, 800.0]:
					at[i] += -sh.height((d * sh.radius + f * m).normalized())
					i += 1
				n += 1
				break
		if n >= 40:
			break
	for i in at.size():
		at[i] /= maxf(n, 1)
	check(n >= 20, "beaches looked out from (%d)" % n)
	check(at[0] < 5.0, "the shallows by the shore: %.1f m deep 40 m out" % at[0])
	check(at[1] < 12.0, "%.1f m deep 100 m out" % at[1])
	check(at[3] > 25.0 and at[3] > at[2] and at[2] > at[1], "dropping off: %.0f m at 200 m, %.0f m at 400 m" % [at[2], at[3]])
	check(at[4] > 40.0, "deep water further out: %.0f m at 800 m" % at[4])


func _cosmos() -> Cosmos:
	Galaxy.current_system = Galaxy.HOME
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


## How far `w` gets swimming (or wading) upstream for `s` seconds from river point `i`
## (+ upstream), Shift held.
func _upstream(w: CosmosWalker, pl: CosmosPlanet, i: int, s: float) -> float:
	var wt := pl.shape.water
	var p := wt.pts[i]
	var way := (wt.pts[i + 1] - wt.pts[i - 1]).normalized()
	w.global_position = pl.to_global(p.normalized() * (pl.radius + wt.lvl[i] - 0.3))
	w.velocity = Vector3.ZERO
	w.current = Vector3.ZERO
	w.heading = pl.dir_world(-way)
	w.drive = {"move": Vector2(0, 1), "run": true}
	var lp0 := pl.to_local(w.global_position)
	for k in int(s * 30.0):
		w._process(1.0 / 30.0)
		w.heading = pl.dir_world(-way)   # (the camera kept upstream)
	w.drive = {}
	return -(pl.to_local(w.global_position) - lp0).dot(way)


func test_rapids_carry_you_off_and_lakes_are_underwater_too() -> void:
	var c := await _cosmos()
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if str(p.rec.get("name", "")) == "Amnissos":
			pl = p
	if not check(pl != null and pl.shape.water != null, "Amnissos is built, its water in"):
		c.queue_free()
		return
	var wt := pl.shape.water
	check(pl.waters != null, "its lakes' and rivers' surfaces (CosmosWaters)")
	var t0 := Time.get_ticks_msec()
	while pl.waters and not pl.waters.built and Time.get_ticks_msec() - t0 < 20000:
		await tree.process_frame
	check(pl.waters.meshes.size() >= wt.lakes.size(), "a mesh for each lake and river (%d)" % pl.waters.meshes.size())
	c.warp_to(c.planets.find(pl), 40.0, 0.0, 0.0, c.land_up(c.planets.find(pl)))
	c.land()
	for k in 200:
		c.ship._process(1.0 / 30.0)
	c.disembark()
	var w := c.walker
	# The fastest, deepest rapids, and a deep, slow stretch.
	var fast := -1
	var calm := -1
	for i in range(1, wt.pts.size() - 1):
		if wt.rid[i - 1] != wt.rid[i] or wt.rid[i + 1] != wt.rid[i] or wt.lake_at(wt.pts[i] / pl.radius) >= 0:
			continue
		if wt.spd[i] > 3.0 and (fast < 0 or wt.dep[i] > wt.dep[fast]):
			fast = i
		if wt.spd[i] < 0.5 and wt.dep[i] > 1.4 and (calm < 0 or wt.dep[i] > wt.dep[calm]):
			calm = i
	check(fast >= 0 and calm >= 0, "rapids (%.1f m/s) and a calm stretch on Amnissos" % (wt.spd[fast] if fast >= 0 else 0.0))
	if fast >= 0 and calm >= 0:
		var f := wt.flow(wt.pts[fast] / pl.radius)
		var way := (wt.pts[fast + 1] - wt.pts[fast - 1]).normalized()
		check(f.dot(way) > 2.5, "the current runs downstream, fast (%.1f m/s)" % f.dot(way))
		var up_fast := _upstream(w, pl, fast, 3.0)
		var up_calm := _upstream(w, pl, calm, 3.0)
		check(w.water_depth > 0.5, "in the water (%.1f m deep)" % w.water_depth)
		check(up_fast < 1.0, "upstream in the rapids: little or no headway - carried off (%.1f m in 3 s)" % up_fast)
		check(up_calm > 3.0, "upstream on a calm stretch: on you go (%.1f m in 3 s)" % up_calm)
		# Let go in the rapids: carried down.
		w.global_position = pl.to_global(wt.pts[fast].normalized() * (pl.radius + wt.lvl[fast] - 0.3))
		w.velocity = Vector3.ZERO
		w.drive = {"move": Vector2.ZERO}
		var lp0 := pl.to_local(w.global_position)
		for k in 60:
			w._process(1.0 / 30.0)
		w.drive = {}
		check((pl.to_local(w.global_position) - lp0).dot(way) > 2.0, "adrift in the rapids: swept downstream (%.1f m in 2 s)" % (pl.to_local(w.global_position) - lp0).dot(way))
	# Swimming out to sea: a gentle stroke at first, building to a fast crawl (as the walk to a run).
	var sea := Vector3.ZERO
	var d0 := pl.to_local(w.global_position).normalized()
	for k in 8000:
		var u := (d0 + Vector3(sin(k * 1.3), cos(k * 2.1), sin(k * 0.7 + 1.0)) * 0.6).normalized()
		if pl.shape.height(u) < -30.0:
			sea = u
			break
	if check(sea != Vector3.ZERO, "deep sea to swim in"):
		w.global_position = pl.to_global(sea * (pl.radius - 0.5))
		w.velocity = Vector3.ZERO
		w.drive = {"move": Vector2(0, 1)}
		var speeds := []
		for k in 13 * 30:
			w._process(1.0 / 30.0)
			if k in [45, 6 * 30, 12 * 30]:
				var u := w.up()
				speeds.append((w.velocity - u * w.velocity.dot(u)).length())
		check(w.swimming, "swimming out at sea")
		check(speeds[0] < CosmosWalker.SWIM_SLOW + 0.4, "a gentle stroke at first (%.1f m/s)" % speeds[0])
		check(speeds[1] > speeds[0] + 0.5 and speeds[2] > CosmosWalker.SWIM_FAST - 0.3, "building to a fast crawl (%.1f, then %.1f m/s)" % [speeds[1], speeds[2]])
		w.drive = {"move": Vector2.ZERO}
		for k in 30:
			w._process(1.0 / 30.0)
		check_eq(w.swim_t, 0.0, "stopped: the stroke back to its gentle start")
		w.drive = {}
	# Under a lake: the underwater look on, the lake's own surface.
	var uw := CosmosUnderwater.new()
	uw.cosmos = c
	c.add_child(uw)
	c.cam.set_process(false)
	c.cam.set_physics_process(false)
	var li := 0
	for k in wt.lakes.size():
		if float(wt.lakes[k]["depth"]) > float(wt.lakes[li]["depth"]):
			li = k
	var ld: Vector3 = wt.lakes[li]["dir"]
	var lv := float(wt.lakes[li]["level"])
	var bottom := pl.shape.height(ld)
	check(bottom < lv - 1.5, "the lake's deep enough to dive in (%.1f m)" % (lv - bottom))
	c.cam.global_position = pl.to_global(ld * (pl.radius + (lv + bottom) * 0.5))
	for k in 20:
		await tree.process_frame
	check(uw.under and not uw.in_sea, "under the lake's surface: the underwater look on (%.1f m down)" % uw.eye_depth)
	check(absf(uw.surface - lv) < 0.05, "its surface the lake's (%.1f m up)" % uw.surface)
	c.cam.global_position = pl.to_global(ld * (pl.radius + lv + 3.0))
	for k in 4:
		await tree.process_frame
	check(not uw.under, "above it: off")
	c.queue_free()
	await tree.process_frame
	await tree.process_frame
