extends TestCase
## Under the sea (CosmosUnderwater): the floor's life scattered by cells round
## the eye - deterministic, only under the water, none on dry land - streamed
## in and out as the eye moves; the underwater look on only while the camera
## is under the surface; the animals kept in the water.

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


## A direction whose floor is between `lo` and `hi` m under the sea (or the driest, hi < 0... see callers).
func _spot(shape: PlanetShape, lo: float, hi: float) -> Vector3:
	for i in 4000:
		var d := Vector3(sin(i * 1.7 + 0.3), cos(i * 2.3), sin(i * 0.9 + 1.0)).normalized()
		var depth := -shape.height(d)
		if depth > lo and depth < hi:
			return d
	return Vector3.ZERO


func _highest(shape: PlanetShape) -> Vector3:
	var best := Vector3.UP
	var bh := -INF
	for i in 3000:
		var d := Vector3(sin(i * 1.3 + 0.7), cos(i * 1.9), sin(i * 0.7 + 2.0)).normalized()
		var h := shape.height(d)
		if h > bh:
			bh = h
			best = d
	return best


static func _positions(buf: PackedFloat32Array, w: int) -> Array:
	var out: Array = []
	for i in buf.size() / w:
		out.append(Vector3(buf[i * w + 3], buf[i * w + 7], buf[i * w + 11]))
	return out


func _area(shape: PlanetShape, dz: Dictionary, d: Vector3) -> Dictionary:
	var keys := CosmosUnderwater.cells_round(shape.radius, d * shape.radius, CosmosUnderwater.RANGE)
	return CosmosUnderwater._build_area(shape, dz, keys, keys, {}, d * shape.radius)


func test_life_only_under_the_sea() -> void:
	var rec := _amnissos_rec()
	check(not rec.is_empty(), "Amnissos is in the home system")
	var shape := PlanetShape.of(rec)
	check_eq(shape.sea, 1, "Amnissos has a sea of water")
	var dz := CosmosUnderwater.design_of(shape, int(rec.get("seed", 1)))
	check(dz["plants"].size() >= 6, "kelp, sea grass, corals, sponges, urchins (%d kinds)" % dz["plants"].size())
	check_eq(dz["fish"].size(), 3, "three kinds of fish")
	var wet := _spot(shape, 6.0, 20.0)
	check(wet != Vector3.ZERO, "a stretch of sea 6-20 m deep")
	var a := _area(shape, dz, wet)
	var n := 0
	var dry := 0
	for i in (a["bufs"] as Array).size():
		for p: Vector3 in _positions(a["bufs"][i], 12):
			n += 1
			if shape.height(p.normalized()) > -0.3 or p.length() > shape.radius:
				dry += 1
	for p: Vector3 in _positions(a["rock_buf"], 16):
		n += 1
		if shape.height(p.normalized()) > -0.3:
			dry += 1
	check(n > 200, "the sea floor round a diver is full of life (%d things)" % n)
	check_eq(dry, 0, "nothing on dry land or above the surface")
	check(not (a["rocks"] as Array).is_empty(), "boulders and corals to bump into")
	# A mountain top: no sea round it, nothing there.
	var top := _highest(shape)
	check(shape.height(top) > 20.0, "Amnissos has high ground (%.0f m)" % shape.height(top))
	var b := _area(shape, dz, top)
	var m := 0
	for i in (b["bufs"] as Array).size():
		m += (b["bufs"][i] as PackedFloat32Array).size() / 12
	m += (b["rock_buf"] as PackedFloat32Array).size() / 16
	check_eq(m, 0, "on a mountain top, no sea life")


func test_cells_are_deterministic() -> void:
	var rec := _amnissos_rec()
	var shape := PlanetShape.of(rec)
	var dz := CosmosUnderwater.design_of(shape, int(rec.get("seed", 1)))
	var wet := _spot(shape, 4.0, 15.0)
	var keys := CosmosUnderwater.cells_round(shape.radius, wet * shape.radius, CosmosUnderwater.RANGE)
	check(keys.size() > 12 and keys.size() < 200, "a few dozen cells round the eye (%d)" % keys.size())
	var same := true
	var any := 0
	for k in keys.slice(0, 6):
		var c1 := CosmosUnderwater.cell(shape, dz, k)
		var c2 := CosmosUnderwater.cell(shape, dz, k)
		for i in (c1["bufs"] as Array).size():
			any += (c1["bufs"][i] as PackedFloat32Array).size()
			same = same and c1["bufs"][i] == c2["bufs"][i]
		same = same and c1["rock_buf"] == c2["rock_buf"]
	check(same, "a cell is built the same every time (its own seed)")
	# Every spot in one cell only: the neighbours' areas overlap, their cells don't double up.
	var k2 := CosmosUnderwater.cells_round(shape.radius, (wet * shape.radius) + wet.cross(Vector3.UP).normalized() * 30.0, CosmosUnderwater.RANGE)
	var shared := keys.filter(func(k): return k2.has(k))
	check(not shared.is_empty() and shared.size() < keys.size(), "moving on, some cells stay and some are new (%d of %d kept)" % [shared.size(), keys.size()])


func _cosmos() -> Cosmos:
	Galaxy.current_system = Galaxy.HOME
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


func _wait(cond: Callable, ms := 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and Time.get_ticks_msec() - t0 < ms:
		await tree.process_frame
	return cond.call()


func test_streamed_round_the_camera_and_on_only_under_water() -> void:
	var c := await _cosmos()
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if str(p.rec.get("name", "")) == "Amnissos":
			pl = p
	if not check(pl != null, "Amnissos is built"):
		c.queue_free()
		return
	var uw := CosmosUnderwater.new()
	uw.cosmos = c
	c.add_child(uw)
	c.cam.set_process(false)
	c.cam.set_physics_process(false)
	var d := _spot(pl.shape, 10.0, 25.0)
	var depth := -pl.shape.height(d)
	c.cam.global_position = pl.to_global(d * (pl.radius - depth * 0.5))
	var ok := await _wait(func(): return uw.planet == pl and not uw.shown_cells.is_empty() and uw._apply.is_empty() and uw._area_task == -1)
	check(ok, "the sea round the camera streamed in")
	await tree.process_frame
	check(uw.under, "the camera %.1f m under the surface is under water" % (depth * 0.5))
	check(uw._fx.visible and uw._glow.visible and uw._snow.visible, "the underwater look on")
	check(uw._root.visible, "the sea's life drawn")
	var atmo := pl.get_node_or_null("Atmosphere") as Node3D
	check(atmo == null or not atmo.visible, "the air's shells not drawn under the sea (covered)")
	var total := 0
	for k in uw.counts:
		total += int(uw.counts[k])
	check(total > 200, "plants, corals and rocks round it (%d)" % total)
	check(uw.counts.get("kelp", 0) + uw.counts.get("seagrass", 0) > 0, "kelp or sea grass")
	check(uw._swimmers.size() >= 7, "fish schools, rays, an eel, jellyfish (%d groups)" % uw._swimmers.size())
	# The animals keep to the water.
	var local := pl.to_local(c.cam.global_position)
	for i in 300:
		uw._swim(0.05, local)
	var wet := 0
	var shown := 0
	for sw in uw._swimmers:
		if not sw.placed:
			continue
		shown += 1
		var h := pl.shape.height(sw.pos.normalized())
		if sw.pos.length() < pl.radius - 0.3 and sw.pos.length() > pl.radius + h - 0.6:
			wet += 1
	check(shown > 0 and wet == shown, "every animal under the surface, over the floor (%d of %d)" % [wet, shown])
	# Up out of the water: the look off, the life hidden (still kept - a dive's ready).
	c.cam.global_position = pl.to_global(d * (pl.radius + 12.0))
	await tree.process_frame
	await tree.process_frame
	check(not uw.under and not uw._fx.visible and not uw._root.visible, "above the surface: nothing of it drawn")
	check(not uw.cells.is_empty(), "...but kept, near the sea")
	check(atmo == null or atmo.visible, "the air's shells back")
	# Swim on: new cells in, the far ones out.
	var before: Array = uw.shown_cells.duplicate()
	var t := d.cross(Vector3.UP).normalized()
	var d2 := (d * pl.radius + t * 60.0).normalized()
	c.cam.global_position = pl.to_global(d2 * (pl.radius - 2.0))
	ok = await _wait(func(): return uw.shown_cells != before and uw._area_task == -1)
	check(ok and uw.shown_cells.any(func(k): return not before.has(k)), "moved on 60 m: new cells streamed in")
	# Far up: all of it let go.
	c.cam.global_position = pl.to_global(d * (pl.radius + 3000.0))
	ok = await _wait(func(): return uw.planet == null, 3000)
	check(ok and uw.cells.is_empty() and uw._root == null, "flown away: the sea's life let go")
	check(not uw._fx.visible, "...and no underwater look")
	c.queue_free()
	await tree.process_frame
	await tree.process_frame
