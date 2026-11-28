extends TestCase
## Landed ships' hulls solid as they're shaped (CosmosHullGrid): a grid of the
## signed distance to a hull's skin a design, made once on a worker - the walker
## held out of it at its skin (not a box round it), free under a high belly,
## stood on its back, its doorway open while its ramp's down; the camera and
## bolts stopped by it; and every design's insides walked into up its ramp, to
## the pilot's seat, and back out.

const EMPS := ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades"]
const DT := 1.0 / 30.0


func setup() -> void:
	if Galaxy.systems.is_empty():
		Galaxy._new_game_begin(true, false)
	Cosmos.arrive_from = ""


func _cosmos() -> Cosmos:
	Galaxy.current_system = "atrapos"
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	c.dry_run = true
	return c


func _on_foot(c: Cosmos) -> CosmosWalker:
	var i := 0
	for k in c.planets.size():
		if (c.planets[k] as CosmosPlanet).shape.sea == 1:
			i = k
			break
	c.warp_to(i, 40.0, 0.0, 0.0, c.land_up(i))
	c.land()
	for k in 200:
		c.ship._process(DT)
	c.disembark()
	return c.walker


## A ship of `emp`'s `hk` hull landed on the ground `ahead` m past your own ship's tail -
## its tail toward you, its legs and ramp down, the foot of its ramp on the ground; its grid made.
func _landed(c: Cosmos, w: CosmosWalker, emp: String, hk: String, ahead := 45.0, seed := 3) -> CosmosNpcShip:
	var x := CosmosNpcShip.new()
	x.setup("trader", c, seed, emp, hk)
	c.world.add_child(x)
	x.set_process(false)   # (held where it's put: not flown)
	x._make_gear()
	x._gear_k = 1.0
	x._ramp_k = 1.0
	x._gear_show()
	c.npc_ships.append(x)
	var pl := w.planet
	var u := w.up()
	var back := c.ship.global_basis.z
	back = (back - u * back.dot(u)).normalized()
	var at := c.ship.global_position + back * (CosmosShip.HULL_R + ahead + x.reach)
	x.global_transform = Transform3D(Basis.looking_at(back, u), at)
	# (its ramp's foot on the ground)
	var foot := x.to_global(x._ramp.position + Vector3(0, -sin(x._ramp_ang), cos(x._ramp_ang)) * x._ramp_len)
	var fl := pl.to_local(foot)
	var ground := pl.to_global(fl.normalized() * (pl.radius + pl.shape.height(fl.normalized())))
	x.global_position += u * (ground - foot).dot(u)
	check(CosmosHullGrid.now(x) != null, "%s %s: its hull's grid made" % [emp, hk])
	c._hulls_at = -1000   # (looked up again now)
	return x


func _ground_at(w: CosmosWalker, p: Vector3) -> Vector3:
	var pl := w.planet
	var l := pl.to_local(p).normalized()
	return pl.to_global(l * (pl.radius + pl.shape.height(l)))


## Walked toward world `to` (`frames` at most, stopping within `near`); each frame the ramps' crossings.
func _walk(c: Cosmos, w: CosmosWalker, to: Vector3, frames: int, near := 0.5) -> void:
	for k in frames:
		var d := to - w.global_position
		d -= w.up() * d.dot(w.up())
		if d.length() < near:
			break
		w.heading = d.normalized()
		w.drive = {"move": Vector2(0, 1)}
		w._process(DT)
		c._npc_boarding()
	w.drive = {}


## The exact distance from `p` (ship space) to a hull's triangles.
static func _mesh_dist(x: Node3D, p: Vector3) -> float:
	var best := INF
	for src in CosmosHullGrid._sources(x)[1]:
		var vs: PackedVector3Array = src[0]
		var xf: Transform3D = src[1]
		var q := xf.affine_inverse() * p
		var k := xf.basis.get_scale().x
		var i := 0
		while i + 2 < vs.size():
			best = minf(best, q.distance_to(_closest(q, vs[i], vs[i + 1], vs[i + 2])) * k)
			i += 3
	return best


## The point of triangle a b c nearest `p`.
static func _closest(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var ab := b - a
	var ac := c - a
	var ap := p - a
	var d1 := ab.dot(ap)
	var d2 := ac.dot(ap)
	if d1 <= 0.0 and d2 <= 0.0:
		return a
	var bp := p - b
	var d3 := ab.dot(bp)
	var d4 := ac.dot(bp)
	if d3 >= 0.0 and d4 <= d3:
		return b
	var vc := d1 * d4 - d3 * d2
	if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
		return a + ab * (d1 / (d1 - d3))
	var cp := p - c
	var d5 := ab.dot(cp)
	var d6 := ac.dot(cp)
	if d6 >= 0.0 and d5 <= d6:
		return c
	var vb := d5 * d2 - d1 * d6
	if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
		return a + ac * (d2 / (d2 - d6))
	var va := d3 * d6 - d5 * d4
	if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	var den := 1.0 / (va + vb + vc)
	return a + ab * (vb * den) + ac * (vc * den)


# --- The grid itself -------------------------------------------------------------------------

## A box's grid: inside negative, outside positive, the distances right to within a cell;
## the same triangles, the same grid (made twice).
func test_grid_measures_a_box() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(6, 3, 10)
	var a := bm.get_mesh_arrays()
	var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var tris := PackedVector3Array()
	for i in idx:
		tris.append(vs[i])
	var out := CosmosHullGrid.make([[tris, Transform3D()]], [])
	var g := CosmosHullGrid._from(out)
	check(g.cell >= CosmosHullGrid.CELL - 0.001, "cells of %.2f m" % g.cell)
	check(g.dist(Vector3.ZERO) < -1.0, "its middle inside (%.2f m)" % g.dist(Vector3.ZERO))
	for p: Vector3 in [Vector3(4.0, 0, 0), Vector3(0, 2.5, 1.0), Vector3(0, 0, -6.2), Vector3(3.6, 2.1, 4.0), Vector3(2.0, 0.5, 0)]:
		var want := CosmosHullGrid._box(p, AABB(-bm.size * 0.5, bm.size)).w
		check(absf(g.dist(p) - want) < g.cell, "at %s: %.2f m from its skin (truly %.2f)" % [p, g.dist(p), want])
	var push := g.push(Vector3(3.2, 0, 0), 0.45)
	check(push.x > 0.1 and absf(push.y) < 0.001, "a ball in its side: out along the ground (%s)" % push)
	check(absf(g.top_below(Vector3(0, 1.0, 0), 0.7) - 1.5) < g.cell, "its top stood on (%.2f m)" % g.top_below(Vector3(0, 1.0, 0), 0.7))
	check(g.top_below(Vector3(0, -0.5, 0), 0.7) == -INF, "in it to over a step: a wall, not a floor")
	var t := g.ray(Vector3(10, 0, 0), Vector3(-1, 0, 0), 20.0)
	check(absf(t - 7.0) < g.cell, "a line meets its side (%.2f m)" % t)
	check(g.ray(Vector3(10, 5, 0), Vector3(-1, 0, 0), 20.0) == INF, "a line over it misses it")
	var door := AABB(Vector3(-1, -1.5, 3.0), Vector3(2, 2.5, 4.0))
	check(g.dist(Vector3(0, -0.5, 4.5), door) > 0.0 and g.dist(Vector3(0, -0.5, 4.5)) < 0.0, "its doorway cut: open there - shut, solid")
	var again := CosmosHullGrid._from(CosmosHullGrid.make([[tris, Transform3D()]], []))
	check_eq(again.digest(), g.digest(), "the same triangles, the same grid")


## Every design's grid: made on a worker, shared by the ships wearing it, the same every time;
## a size and a solid fit for it.
func test_grids_of_every_design() -> void:
	var made := {}
	for emp in EMPS:
		for hk in ["shuttle", "trader", "fighter"]:
			var s := CosmosNpcShip.new()
			tree.root.add_child(s)
			s.setup("trader", null, 3, emp, hk)
			var g := CosmosHullGrid.of(s)
			var t0 := Time.get_ticks_msec()
			while g == null and Time.get_ticks_msec() - t0 < 30000:
				await tree.process_frame
				g = CosmosHullGrid.of(s)
			var tag := "%s %s" % [emp, hk]
			check(g != null, "%s: its grid made on a worker" % tag)
			if g == null:
				s.free()
				continue
			var hb: AABB = s._hull_box()
			check(g.bounds.grow(g.cell * 2.0).encloses(hb), "%s: the grid's solid as big as its hull (%s, %s)" % [tag, g.bounds.size, hb.size])
			check(g.solid > 500, "%s: solid cells (%d)" % [tag, g.solid])
			var key := str(s.get_meta("hull_grid_key"))
			if made.has(key):
				check(made[key] == g, "%s: one grid shared by a design's ships" % tag)
			else:
				made[key] = g
				var src := CosmosHullGrid._sources(s)
				check_eq(CosmosHullGrid._from(CosmosHullGrid.make(src[1], src[2])).digest(), g.digest(), "%s: made again, the same grid" % tag)
			var s2 := CosmosNpcShip.new()
			tree.root.add_child(s2)
			s2.setup("trader", null, 3, emp, hk)
			check(CosmosHullGrid.of(s2) == g, "%s: a second ship of its design - its grid at once" % tag)
			s2.free()
			s.free()


# --- Walking round it --------------------------------------------------------------------------

## Walked into a hull's side: stopped at its skin (your body a ball's radius off it, within a cell) -
## inside the box round it; under a belly too low for you, stopped; under a high one, free;
## a jet's fall onto its back - stood on it; the camera kept out of it; bolts struck on it.
func test_walker_held_at_the_hull_skin() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var x := _landed(c, w, "athens", "trader")
	var g := CosmosHullGrid.of(x)
	var hb: AABB = x._hull_box()
	var r := CosmosWalker.BODY_R
	# Where its skin at your height (over the ground there) is well in from its box's side.
	var best_z := INF
	var best_x := INF
	var feet := 0.0
	for i in range(int(hb.position.z) + 2, int(hb.end.z) - 2):
		var k := 0
		while hb.end.x - k * 0.2 > hb.get_center().x:
			var px := hb.end.x - k * 0.2
			k += 1
			var fy := x.to_local(_ground_at(w, x.to_global(Vector3(px, 0, i)))).y
			if g.dist(Vector3(px, fy + 1.15, i)) < -0.2:   # (its side, square across your body - not a belly over your head)
				if px < best_x:
					best_x = px
					best_z = i
					feet = fy
				break
	check(best_z < INF and best_x < hb.end.x - 1.0, "a side of it, at your height, in from its box (%.1f of %.1f m)" % [best_x, hb.end.x])
	var start := _ground_at(w, x.to_global(Vector3(best_x + 2.5, 0, best_z)))
	w.global_position = start
	w.velocity = Vector3.ZERO
	await _frames(1)
	_walk(c, w, _ground_at(w, x.to_global(Vector3(best_x - 8.0, 0, best_z))), 90, 0.2)
	var l := x.to_local(w.global_position)
	var gap := INF
	for h: float in Cosmos.HULL_PROBES:
		gap = minf(gap, _mesh_dist(x, l + Vector3(0, h, 0)))
	check(w.deck == null, "on the ground still")
	check(absf(gap - r) < g.cell + 0.05, "stopped at its skin: your body %.2f m off it (a ball's %.2f, within a %.2f m cell)" % [gap, r, g.cell])
	check(l.x < hb.end.x + r - 0.8, "not at a box round it: %.2f m in from its box's side" % (hb.end.x + r - l.x))
	# Its belly too low to walk under (a trader's: on short legs): kept out from under it.
	var under := _ground_at(w, x.to_global(Vector3(0, 0, hb.get_center().z)))
	var ul := x.to_local(under)
	if g.dist(ul + Vector3(0, 1.4, 0)) < 0.0:
		w.global_position = under
		c.walker_bumps(w)
		var moved := x.to_local(w.global_position)
		check(g.dist(moved + Vector3(0, 1.15, 0)) > 0.0 or (moved - ul).length() > 0.5, "under its belly too low for you: not let in (%s)" % (moved - ul))
	# The camera's line through it: stopped short, outside it.
	var pivot := x.to_global(Vector3(best_x + 2.5, feet + 1.3, best_z))
	var want := x.to_global(Vector3(best_x - 6.0, feet + 1.3, best_z))
	var cam := c.camera_clear(pivot, want)
	check(cam.distance_to(pivot) < pivot.distance_to(want) * 0.8 and g.dist(x.to_local(cam)) > 0.05, "the camera kept out of its hull (%.2f m off it)" % g.dist(x.to_local(cam)))
	# A bolt at it: struck on its skin, not through it.
	var bolt := CosmosBolt.fire(c, pivot, (want - pivot).normalized(), "player", 1.0)
	var hit := bolt.step(pivot, want)
	var at := x.to_local(bolt._hit)
	check(hit and absf(g.dist(at)) < g.cell, "a bolt struck on its skin (%.2f m off it)" % g.dist(at))
	bolt.queue_free()
	c.queue_free()
	await _frames(2)


## Under a high belly (a hauler's, on its long legs): walked under, free; on its back - jetted
## up and dropped onto it: stood on its top, not fallen through.
func test_under_a_belly_and_on_its_back() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var x := _landed(c, w, "sparta", "hauler", 60.0)
	var g := CosmosHullGrid.of(x)
	var hb: AABB = x._hull_box()
	var free := 0
	var held := 0
	for i in 12:
		var p := _ground_at(w, x.to_global(Vector3(hb.get_center().x + (i - 6) * 1.5, 0, hb.get_center().z + 3.0)))
		var lp := x.to_local(p)
		if g.dist(lp + Vector3(0, 1.9, 0)) < 0.5:
			continue   # (its belly not over your head here)
		w.global_position = p
		c.walker_bumps(w)
		if w.global_position.distance_to(p) < 0.001:
			free += 1
		else:
			held += 1
	check(free >= 6 and held == 0, "under its high belly: walked free (%d places, %d held)" % [free, held])
	# On its back.
	var mid := Vector3(hb.get_center().x, hb.end.y + 3.0, hb.get_center().z)
	var top := g.top_below(mid - Vector3(0, 3.0, 0) + Vector3(0, 0.1, 0), 3.0)
	check(top > hb.position.y, "its back's top found (%.2f m)" % top)
	w.global_position = x.to_global(Vector3(mid.x, top + 2.5, mid.z))
	w.velocity = Vector3.ZERO
	w.on_ground = false
	c._hulls_at = -1000
	c._hulls_near(w)
	for k in 90:
		w._process(DT)
	var l := x.to_local(w.global_position)
	check(w.on_ground and absf(l.y - top) < 0.15, "dropped onto its back: standing on it (%.2f m over its top)" % (l.y - top))
	w.drive = {"move": Vector2(0, 1)}
	w.heading = x.global_basis.z
	for k in 15:
		w._process(DT)
	w.drive = {}
	l = x.to_local(w.global_position)
	check(w.on_ground and absf(l.y - g.top_below(l + Vector3(0, 0.2, 0), 0.7)) < 0.15, "walked along its back, on it")
	c.queue_free()
	await _frames(2)


## Your own ship landed: its hull solid outside too (its tail's doorway open while its ramp's down).
func test_own_ship_hull_solid() -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var g := CosmosHullGrid.now(c.ship)
	check(g != null, "your hull's grid")
	c._hulls_at = -1000
	c._hulls_near(w)
	check(c._hulls.any(func(e): return e[0] == c.ship), "your landed ship's hull solid to you")
	var side := _ground_at(w, c.ship.to_global(Vector3(2.0, 0, 0)))
	w.global_position = side
	c.walker_bumps(w)
	var l := c.ship.to_local(w.global_position)
	check(g.dist(l + Vector3(0, 1.15, 0)) >= CosmosWalker.BODY_R - g.cell * 0.5 or g.dist(l + Vector3(0, 1.4, 0)) >= CosmosWalker.BODY_R - g.cell * 0.5 or absf(l.x) > 2.0,
		"stood in its side: held out of it (%s)" % l)
	var door: AABB = c.ship.door_box()
	check(door.size != Vector3.ZERO, "its ramp down: its tail's doorway open")
	var in_door := Vector3(0, CosmosShipInterior.FLOOR + 1.0, float(CosmosShipInterior.RAMP[1]) - 0.3)
	check(g.dist(in_door, door) > 0.0 and g.dist(in_door) < 0.0, "the doorway cut through its hull (shut: solid)")
	c.queue_free()
	await _frames(2)


# --- Walking in ---------------------------------------------------------------------------------

## Each empire's shuttle and trader: up its ramp from the ground, in through its door, forward
## to the pilot's seat and back out; the hull never in the way. Its courier's skiff: no room
## inside - its hull shut, solid all round. Its ramp up: the doorway shut, solid.
func _walk_in(emp: String) -> void:
	var c := await _cosmos()
	var w := _on_foot(c)
	var ahead := 40.0
	for hk in ["shuttle", "trader", "fighter"]:
		var x := _landed(c, w, emp, hk, ahead)
		ahead += 10.0
		x.traffic = RefCounted.new()   # (a town's field's ship, down on its pad: walked into)
		var tag := "%s %s" % [emp, hk]
		var inn := x.make_interior()
		var t0 := Time.get_ticks_msec()
		while not inn.built and Time.get_ticks_msec() - t0 < 10000:
			await tree.process_frame
		var g := CosmosHullGrid.of(x)
		var foot := inn.to_global(inn.foot)
		var behind := _ground_at(w, inn.to_global(inn.foot + Vector3(0, 0, 3.0)))
		w.global_position = behind
		w.velocity = Vector3.ZERO
		w.set_deck(null)
		c._hulls_at = -1000
		if hk == "fighter":
			check(not inn.ok, "%s: a courier's skiff - no room inside" % tag)
			check(x.door_box().size == Vector3.ZERO, "%s: no doorway in its hull" % tag)
			check(g.dist(x._hull_box().get_center()) < 0.0, "%s: its hull solid through" % tag)
			_walk(c, w, foot, 200, 0.4)
			_walk(c, w, x.global_position, 120, 0.4)
			var lw := x.to_local(w.global_position)
			check(w.deck == null and minf(g.dist(lw + Vector3(0, 1.15, 0)), g.dist(lw + Vector3(0, 1.4, 0))) > 0.0, "%s: up its ramp and on: not into it" % tag)
			x.queue_free()
			c.npc_ships.erase(x)
			continue
		check(inn.ok and inn.pilot_pos != Vector3.INF, "%s: its insides made, a pilot's seat" % tag)
		if not inn.ok:
			continue
		# The doorway and the hull agree: open while the ramp's down - shut it, solid.
		var sill := Vector3(0, inn.sill + 1.2, inn.door.position.z + 0.6)   # (in its doorway, through its hull at its rooms' aft end)
		check(g.dist(sill, x.door_box()) > CosmosWalker.BODY_R, "%s: its doorway open to walk through" % tag)
		x._ramp_k = 0.0
		var shut := g.ray(Vector3(0, sill.y, inn.z_aft + 6.0), Vector3(0, 0, -1), 60.0, x.door_box())
		check(x.door_box().size == Vector3.ZERO and inn.z_aft + 6.0 - shut >= inn.door.position.z - 0.1 and (g.dist(sill) < 0.0 or inn.door.position.z > inn.z_aft - 6.0),
			"%s: its ramp up - its doorway shut, solid (a line in stopped at %.1f m)" % [tag, inn.z_aft + 6.0 - shut])
		x._ramp_k = 1.0
		# Up its ramp, through its rooms to the pilot's seat.
		_walk(c, w, foot, 200, 0.3)
		var seat := inn.to_global(inn.pilot_pos)
		var was_aboard := false
		for k in 900:
			if w.deck == inn:
				was_aboard = true
			var d := seat - w.global_position
			d -= w.up() * d.dot(w.up())
			if d.length() < 1.1:
				break
			# (down the middle of it: through its doorways, to the seat)
			var lw := inn.to_local(w.global_position)
			var aim := inn.to_global(Vector3(0, lw.y, lw.z - 2.0)) if absf(lw.x) > 0.25 or lw.z > inn.pilot_pos.z + 3.0 else seat
			var dd := aim - w.global_position
			dd -= w.up() * dd.dot(w.up())
			w.heading = dd.normalized()
			w.drive = {"move": Vector2(0, 1)}
			w._process(DT)
			c._npc_boarding()
		w.drive = {}
		var reach := (seat - w.global_position).length()
		check(was_aboard and w.deck == inn, "%s: up its ramp and in, aboard" % tag)
		check(reach < 1.6, "%s: forward to the pilot's seat (%.2f m from it)" % [tag, reach])
		# Back out: aft through its rooms, down the ramp, onto the ground.
		var out := _ground_at(w, inn.to_global(inn.foot + Vector3(0, 0, 4.0)))
		for k in 900:
			if w.deck == null:
				break
			var lw := inn.to_local(w.global_position)
			var aim := inn.to_global(Vector3(0, lw.y, lw.z + 2.0))
			var dd := aim - w.global_position
			dd -= w.up() * dd.dot(w.up())
			w.heading = dd.normalized()
			w.drive = {"move": Vector2(0, 1)}
			w._process(DT)
			c._npc_boarding()
		w.drive = {}
		check(w.deck == null and w.planet != null, "%s: down its ramp, back on the ground" % tag)
		var p0 := w.global_position
		_walk(c, w, out, 60, 0.3)
		check(w.global_position.distance_to(out) < 1.0 and w.global_position.distance_to(p0) > 0.3, "%s: walked off from its ramp's foot, nothing in the way" % tag)
		x.queue_free()
		c.npc_ships.erase(x)
	c.queue_free()
	await _frames(2)


func test_walk_into_minoan_ships() -> void:
	await _walk_in("minoa")


func test_walk_into_athenian_ships() -> void:
	await _walk_in("athens")


func test_walk_into_spartan_ships() -> void:
	await _walk_in("sparta")


func test_walk_into_mycenaean_ships() -> void:
	await _walk_in("mycenae")


func test_walk_into_ionian_ships() -> void:
	await _walk_in("ionia")


func test_walk_into_cycladic_ships() -> void:
	await _walk_in("cyclades")


func _frames(n: int) -> void:
	for i in n:
		await tree.process_frame
