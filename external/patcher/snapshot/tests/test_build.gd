extends TestCase
## The building kit (BuildKit, BuildPlan, CosmosStructure, CosmosBuilds): every
## piece built in every tier and style, snapping to sockets, support and what
## falls, costs and refunds, walking in and on what's built (walls, doorways,
## doors, ceilings, stairs), and structures kept through a save.


func _cosmos(sid := "atrapos") -> Cosmos:
	Galaxy.current_system = sid
	var c: Cosmos = load(Cosmos.SCENE).instantiate()
	tree.root.add_child(c)
	var t0 := Time.get_ticks_msec()
	while not c.build_settled() and Time.get_ticks_msec() - t0 < 30000:
		await tree.process_frame
	return c


static func _pc(t: String, p: Vector3, r := 0, m := 1, s := "minoa") -> Dictionary:
	return {"t": t, "p": BuildKit.arr(p), "r": r, "m": m, "s": s, "c": 0}


func test_every_piece_builds_in_every_tier() -> void:
	var worst := 0
	var bad := []
	for id in BuildKit.PIECES:
		for m in BuildKit.TIERS.size():
			for s in ["minoa", "athens", "mycenae", "cyclades"]:
				var b := CosmosTown.Builder.new()
				var pc := _pc(id, Vector3(4, 3.2, 8), 1, m, s)
				pc["d"] = 1.5
				var res := BuildKit.emit(b, pc)
				var n := b.verts.size()
				worst = maxi(worst, n)
				if n == 0 and id != "steps":
					bad.append("%s/%d/%s: no faces" % [id, m, s])
				if b.idx.size() % 3 != 0 or b.verts.size() != b.cols.size() or b.verts.size() != b.norms.size():
					bad.append("%s: broken arrays" % id)
				if (res["solids"] as Array).is_empty() and BuildKit.kind(id) != "free" and id != "sconce":
					bad.append("%s/%d: nothing solid" % [id, m])
	check(bad.is_empty(), "every piece has faces and solids (%s)" % ", ".join(bad.slice(0, 6)))
	check(worst < 4000, "no piece too heavy (%d vertices at most)" % worst)
	check(BuildKit.PIECES.size() >= 35, "an extensive kit (%d pieces)" % BuildKit.PIECES.size())
	for cat in BuildKit.CATS:
		check(not BuildKit.ids_in(str(cat[0])).is_empty(), "%s: pieces in it" % cat[1])
	# Movers: a door has a leaf, a gate two, a window two shutters, a hatch its lid.
	for e in [["door", 1], ["gate", 2], ["window", 2], ["hatch", 1], ["fence_gate", 1]]:
		var res := BuildKit.emit(CosmosTown.Builder.new(), _pc(e[0], Vector3.ZERO))
		check_eq((res["movers"] as Array).size(), e[1], "%s: its hinged leaves" % e[0])
	check(not (BuildKit.emit(CosmosTown.Builder.new(), _pc("lamp", Vector3.ZERO))["lights"] as Array).is_empty(), "a brazier lights")
	check(not (BuildKit.emit(CosmosTown.Builder.new(), _pc("chest", Vector3.ZERO))["uses"] as Array).is_empty(), "a chest is used")


func test_snapping_to_sockets() -> void:
	var plan := BuildPlan.new([])
	var f0 := plan.snap("foundation", Vector3(1, 0, 1))
	check(BuildKit.vec(f0["p"]) == Vector3.ZERO, "the first foundation: the structure's middle")
	plan.add(_pc("foundation", Vector3.ZERO))
	var f1 := plan.snap("foundation", Vector3(5.2, 0.2, 0.6))
	check(BuildKit.vec(f1["p"]).distance_to(Vector3(4, 0, 0)) < 0.01, "a foundation snaps beside another (%s)" % str(f1["p"]))
	check_eq(plan.check(f1.merged({"m": 1})), "", "and fits")
	plan.add(_pc("foundation", Vector3(4, 0, 0)))
	var tri := plan.snap("foundation_tri", Vector3(0.3, 0.1, -3.0))
	var tp := BuildKit.vec(tri["p"])
	check(absf(tp.z + 2.0 + BuildKit.TRI_R) < 0.01 and absf(tp.x) < 0.01, "a triangle against an edge (%s)" % str(tp))
	check_eq(plan.check(tri.merged({"m": 1})), "", "the triangle fits")
	plan.add(tri.merged({"m": 1, "s": "minoa"}))
	# A triangle's slanted edge takes a square at 30 degrees.
	var sq := plan.snap("foundation", tp + Vector3(-2.0, 0, -1.6))
	check(not sq.is_empty() and int(sq["r"]) % 3 != 0, "a square off a triangle's slant, turned off the grid (r %s)" % str(sq.get("r")))
	check_eq(plan.check(sq.merged({"m": 1})), "", "and fits beside it")
	# Walls on the foundation's edges, facing out.
	var w := plan.snap("wall", Vector3(-2.1, 1.4, 0.2))
	check(BuildKit.vec(w["p"]).distance_to(Vector3(-2, 0, 0)) < 0.01, "a wall on the foundation's edge (%s)" % str(w["p"]))
	for p in [Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(6, 0, 0), Vector3(4, 0, 2)]:
		var ww := plan.snap("wall", p + Vector3(0, 1.5, 0))
		check_eq(plan.check(ww.merged({"m": 1})), "", "a wall at %s fits" % str(p))
		plan.add(ww.merged({"m": 1, "s": "minoa"}))
	var dup := plan.snap("wall", Vector3(-2, 1.5, 0))
	check(plan.check(dup.merged({"m": 1})) != "", "one wall an edge")
	# A wall on a wall (the next storey); a ceiling on the walls' tops.
	var w2 := plan.snap("wall", Vector3(-2, 4.6, 0))
	check(absf(BuildKit.vec(w2["p"]).y - BuildKit.WALL_H) < 0.01, "a wall stacked on a wall (%s)" % str(w2["p"]))
	var ceil := plan.snap("floor", Vector3(0.5, 3.3, 0.2))
	check(BuildKit.vec(ceil["p"]).distance_to(Vector3(0, BuildKit.WALL_H, 0)) < 0.01, "a ceiling on the walls (%s)" % str(ceil["p"]))
	# A pillar on a corner; stairs in a cell, turned a quarter.
	var pil := plan.snap("pillar", Vector3(5.8, 1.0, -1.8))
	check(BuildKit.vec(pil["p"]).distance_to(Vector3(6, 0, -2)) < 0.01, "a pillar on a corner (%s)" % str(pil["p"]))
	var st0 := plan.snap("stairs", Vector3(4, 1, 0))
	var st1 := plan.snap("stairs", Vector3(4, 1, 0), 1)
	check(BuildKit.vec(st0["p"]).distance_to(Vector3(4, 0, 0)) < 0.01 and posmod(int(st1["r"]) - int(st0["r"]), 12) == 3, "stairs in a cell, K turns them a quarter")
	# Furniture on a floor's half metre grid.
	var ch := plan.snap("chest", Vector3(0.62, 0.0, -0.9))
	check(BuildKit.vec(ch["p"]).distance_to(Vector3(0.5, 0, -1.0)) < 0.01, "a chest set square on the floor (%s)" % str(ch["p"]))


func test_support_spans_and_what_falls() -> void:
	var plan := BuildPlan.new([])
	plan.add(_pc("foundation", Vector3.ZERO))
	var walls := []
	for e in BuildKit.edges(plan.pieces[0]):
		walls.append(plan.add(_pc("wall", e[2], BuildKit.r_facing(e[3]))))
	check_eq(int(plan.spans[0]), 3, "a stone foundation holds 3")
	check_eq(int(plan.spans[walls[0]]), 3, "a wall on it carries its span")
	var ceil := _pc("floor", Vector3(0, BuildKit.WALL_H, 0))
	check_eq(plan.check(ceil), "", "a ceiling on four walls")
	plan.add(ceil)
	# Out from the walls a cell at a time: the cell over a wall holds its span, each further one less.
	var out := []
	for k in range(1, 5):
		var q := _pc("floor", Vector3(4 * k, BuildKit.WALL_H, 0))
		out.append(plan.check(q))
		if out[-1] == "":
			plan.add(q)
	check(out[0] == "" and out[1] == "" and out[2] == "", "stone: two cells out past the one over the wall (%s)" % str(out))
	check(out[3].begins_with("Too far"), "the next too far from a support (%s)" % out[3])
	var t1 := _pc("floor", Vector3(0, BuildKit.WALL_H, 4.0), 0, 0)
	check_eq(plan.check(t1), "", "timber over the wall")
	plan.add(t1)
	var t2 := _pc("floor", Vector3(0, BuildKit.WALL_H, 8.0), 0, 0)
	check_eq(plan.check(t2), "", "timber: one cell out")
	plan.add(t2)
	check(plan.check(_pc("floor", Vector3(0, BuildKit.WALL_H, 12.0), 0, 0)) != "", "timber: not two")
	# All bronze: three cells out.
	var bp := BuildPlan.new([_pc("foundation", Vector3.ZERO, 0, 3)])
	for e in BuildKit.edges(bp.pieces[0]):
		bp.add(_pc("wall", e[2], BuildKit.r_facing(e[3]), 3))
	var bo := []
	for k in range(1, 6):
		var q := _pc("floor", Vector3(-4 * k, BuildKit.WALL_H, 0), 0, 3)
		bo.append(bp.check(q))
		if bo[-1] == "":
			bp.add(q)
	check(bo.slice(0, 4).all(func(r): return r == "") and bo[4] != "", "bronze reaches further (%s)" % str(bo))
	check(plan.check(_pc("wall", Vector3(30, 0, 0))) == "Nothing holds it up", "a wall on nothing")
	# Take a wall away: the ceiling's still held by the other three. The foundation: all of it.
	var falls := plan.falling(walls[0])
	check_eq(falls.size(), 1, "one wall less: nothing else falls")
	var n0 := plan.pieces.size()
	var gone := plan.remove(0)
	check_eq(gone.size(), n0, "the foundation taken: everything on it falls (%d of %d)" % [gone.size(), n0])
	check(plan.pieces.is_empty(), "nothing left standing")


func test_costs_and_refunds() -> void:
	if CosmosGame.data == null:
		CosmosGame._fresh_data()
		await tree.process_frame
	var d: Node = CosmosGame.data
	d.items.erase("stone")
	d.carried.erase("stone")
	check_eq(BuildKit.cost("wall", 1), {"stone": 4}, "a stone wall: 4 stone")
	check(BuildKit.cost("wall", 0).has("timber"), "a timber one: timber")
	check(BuildKit.cost("wall", 3).has("bronze_ingots"), "a bronze one: bronze ingots")
	d.carried["stone"] = 3
	d.add_item("stone", 5)
	check_eq(CosmosBuilds.have("stone"), 8, "what you carry and the hold")
	CosmosBuilds.spend({"stone": 4})
	check(int(d.carried.get("stone", 0)) == 0 and d.count("stone") == 4, "spent: the carried first, then the hold")
	var pc := _pc("wall", Vector3.ZERO)
	pc["at"] = Time.get_unix_time_from_system()
	check_eq(BuildKit.refund(pc, Time.get_unix_time_from_system() + 5.0), {"stone": 4}, "taken down within a minute: all back")
	check_eq(BuildKit.refund(pc, Time.get_unix_time_from_system() + 600.0), {"stone": 2}, "later: half")
	var up := CosmosBuilds.upgrade_cost(_pc("wall", Vector3.ZERO, 0, 1))
	check(up.has("marble") and up.has("stone"), "an upgrade: the next tier's materials (%s)" % str(up))
	d.items.erase("stone")


## A little house on a level frame: foundations, walls, a doorway or door, a ceiling, stairs.
func _house(st: CosmosStructure, door := "doorway") -> void:
	var plan := st.plan
	plan.add(_pc("foundation", Vector3.ZERO))
	plan.add(_pc("foundation", Vector3(4, 0, 0)))
	for e in BuildKit.edges(plan.pieces[0]):
		var m: Vector3 = e[2]
		if m.x > 1.0:
			continue
		plan.add(_pc(door if m.z < -1.0 else "wall", m, BuildKit.r_facing(e[3])))
	plan.add(_pc("floor", Vector3(0, BuildKit.WALL_H, 0)))
	plan.add(_pc("stairs", Vector3(4, 0, 0), 0))
	for pc in plan.pieces:
		pc["d"] = 1.0
	plan.reindex()
	st.extent()
	st.mark_all()


func _wait_built(st: CosmosStructure) -> void:
	var t0 := Time.get_ticks_msec()
	while st.busy() and Time.get_ticks_msec() - t0 < 10000:
		await tree.process_frame


func test_walking_in_what_is_built() -> void:
	var st := CosmosStructure.new()
	st.setup(null, {"o": [0, 1000, 0], "x": [1, 0, 0], "pieces": []})
	tree.root.add_child(st)
	_house(st)
	await _wait_built(st)
	check(st.is_built() and st.get_child_count() > 0, "its chunks in (%d solids)" % st._solids.size())
	check(absf(st.floor_top(Vector3(0, 0.1, 0))) < 0.01, "standing on the foundation")
	check(absf(st.floor_top(Vector3(0, 3.5, 0)) - BuildKit.WALL_H) < 0.01, "on the ceiling, up top")
	check(st.indoors(Vector3(0, 0.05, 0)), "indoors under it")
	# Walls hold you in: a body at the -x wall pushed back inside.
	var push := st.push(Vector3(-1.95, 0.05, 0.3), CosmosWalker.BODY_R)
	check(push.x > 0.2, "the wall pushes you back in (%s)" % str(push))
	# The doorway (-z side) lets you through.
	var dp := st.push(Vector3(0, 0.05, -2.0), CosmosWalker.BODY_R)
	check(dp.length() < 0.05, "through the doorway (%s)" % str(dp))
	# Up the stairs (in the +x cell, climbing along +z).
	var p := Vector3(4, 0.0, -2.3)
	var top := 0.0
	for k in 160:
		p.z += 0.03
		var f := st.floor_top(p)
		if f >= p.y - 0.01:
			p.y = f
		top = maxf(top, p.y)
	check(top > BuildKit.WALL_H - 0.05, "up the stairs to the next floor (%.2f m)" % top)
	st.queue_free()
	await tree.process_frame
	# A door: shut, it blocks the doorway; opened, it swings out of the way.
	var st2 := CosmosStructure.new()
	st2.setup(null, {"o": [0, 1000, 0], "x": [1, 0, 0], "pieces": []})
	tree.root.add_child(st2)
	_house(st2, "door")
	await _wait_built(st2)
	check_eq(st2.movers.size(), 1, "the door's leaf hung")
	var shut := st2.push(Vector3(0, 0.05, -2.0), CosmosWalker.BODY_R)
	check(shut.length() > 0.1, "a shut door blocks (%s)" % str(shut))
	var door: Dictionary = st2.plan.pieces.filter(func(q): return q["t"] == "door")[0]
	st2.toggle(door)
	for k in 90:
		await tree.process_frame
	var open := st2.push(Vector3(0, 0.05, -2.0), CosmosWalker.BODY_R)
	check(open.length() < 0.05 and bool(door["o"]), "opened: through it (%s)" % str(open))
	st2.queue_free()
	await tree.process_frame


func test_built_and_kept_through_save_and_return() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if p.shape.kind == "rocky":
			pl = p
			break
	var pid := CosmosBuilds.pid_of(pl)
	var d := Vector3(0.2, 0.9, 0.4).normalized()
	var o := d * (pl.radius + pl.shape.height(d) + 0.4)
	var x := d.cross(Vector3.UP).normalized()
	CosmosGame.data.add_item("stone", 200)
	# The builder places a foundation (a new structure there) and walls on it.
	c.builds._sync_t = 1e9   # (its world set by hand)
	c.builds.planet = pl
	c.builds.aim_frame = Transform3D(Basis(x, d, x.cross(d)), o)
	var ok := c.builds.place(null, _pc("foundation", Vector3.ZERO))
	check(ok and c.builds.structures.size() == 1, "a foundation starts a structure")
	var st: CosmosStructure = c.builds.structures[0]
	var placed := 0
	for e in BuildKit.edges(st.plan.pieces[0]):
		if c.builds.place(st, _pc("wall", e[2], BuildKit.r_facing(e[3]))):
			placed += 1
	check_eq(placed, 4, "four walls on it")
	check(c.builds.place(st, _pc("floor", Vector3(0, BuildKit.WALL_H, 0))), "a ceiling on them")
	var recs: Array = CosmosGame.extra["structures"][pid]
	check(recs.size() == 1 and (recs[0]["pieces"] as Array).size() == 6, "in the save's extras")
	var stj: Dictionary = JSON.parse_string(JSON.stringify(CosmosGame.snapshot(c)))
	c.queue_free()
	await tree.process_frame
	await tree.process_frame
	CosmosGame.begin_state(stj)
	var c2 := await _cosmos()
	var recs2: Array = CosmosGame.extra.get("structures", {}).get(pid, [])
	check(recs2.size() == 1 and (recs2[0]["pieces"] as Array).size() == 6, "loaded: the structure's 6 pieces")
	var pl2: CosmosPlanet = null
	for p: CosmosPlanet in c2.planets:
		if CosmosBuilds.pid_of(p) == pid:
			pl2 = p
	c2.builds._sync_t = 1e9
	c2.builds.planet = pl2
	c2.builds.reload()
	var st2: CosmosStructure = c2.builds.structures[0] if not c2.builds.structures.is_empty() else null
	check(st2 != null, "raised again on its world")
	if st2:
		await _wait_built(st2)
		var top := c2.builds.floor_at(pl2, o + d * 3.4)
		check(absf(top - (o.length() + BuildKit.WALL_H - pl2.radius)) < 0.05, "its ceiling stood on again (%.2f)" % top)
	c2.queue_free()
	await tree.process_frame


## The towns' buildings: the kit's pieces in each empire's style - walls,
## doorways, windows, floors, stairs, flat roofs - one mesh a town, its solids
## all boxes (the town plans draw them), every building with a way in.
func test_towns_built_from_the_kit() -> void:
	for emp in ["minoa", "athens", "sparta", "mycenae", "ionia", "cyclades"]:
		for kind in ["city", "village"]:
			var t0 := Time.get_ticks_usec()
			var made := CosmosTown._make(kind, 5, emp)
			var ms := (Time.get_ticks_usec() - t0) / 1000.0
			var nv := 0
			for m: ArrayMesh in made["meshes"]:
				nv += (m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			print("TOWN %s %s: %d vertices, %d solids, %d doors, %.0f ms" % [emp, kind, nv, (made["solids"] as Array).size(), (made["doors"] as Array).size(), ms])
			check((made["meshes"] as Array).size() >= 2 and (made["meshes"] as Array).size() <= 30, "%s %s: a mesh a block (%d)" % [emp, kind, (made["meshes"] as Array).size()])
			check(nv < 560000, "%s %s: not too heavy (%d vertices)" % [emp, kind, nv])
			check((made["solids"] as Array).all(func(b): return b is AABB), "%s %s: its solids all boxes" % [emp, kind])
			check((made["doors"] as Array).size() >= (12 if kind == "city" else 4), "%s %s: buildings with doorways (%d)" % [emp, kind, (made["doors"] as Array).size()])


func test_half_and_quarter_plates() -> void:
	var plan := BuildPlan.new([])
	plan.add(_pc("foundation", Vector3.ZERO))
	# A half against the +x edge: long side on it (2 m deep), or turned: its short side on it, 4 m out.
	var h := plan.snap("foundation_half", Vector3(3.0, 0, 0.2))
	check(BuildKit.vec(h["p"]).distance_to(Vector3(3, 0, 0)) < 0.01, "a half foundation against an edge, 2 m deep (%s)" % str(h["p"]))
	check_eq(plan.check(h.merged({"m": 1})), "", "it fits")
	var ht := plan.snap("foundation_half", Vector3(4.0, 0, 1.0), 1)
	check(not ht.is_empty() and absf(BuildKit.vec(ht["p"]).x - 4.0) < 0.01 and absf(absf(BuildKit.vec(ht["p"]).z) - 1.0) < 0.01, "turned: its short side on the edge, along a half of it (%s)" % str(ht.get("p")))
	plan.add(h.merged({"m": 1, "s": "minoa"}))
	# Quarters: two places along a cell's edge, side by side.
	var q1 := plan.snap("foundation_quarter", Vector3(-0.9, 0, -2.9))
	var q2 := plan.snap("foundation_quarter", Vector3(1.1, 0, -2.9))
	check(BuildKit.vec(q1["p"]).distance_to(Vector3(-1, 0, -3)) < 0.01 and BuildKit.vec(q2["p"]).distance_to(Vector3(1, 0, -3)) < 0.01,
		"quarters along a cell's edge, side by side (%s, %s)" % [str(q1["p"]), str(q2["p"])])
	plan.add(q1.merged({"m": 1, "s": "minoa"}))
	check(plan.check(q1.merged({"m": 1})) != "", "a quarter's place taken")
	check_eq(plan.check(q2.merged({"m": 1})), "", "the other free")
	# A balcony: a half floor out from a ceiling's edge, held by the ceiling a cell out.
	var bp := BuildPlan.new([])
	bp.add(_pc("foundation", Vector3.ZERO))
	for e in BuildKit.edges(bp.pieces[0]):
		bp.add(_pc("wall", e[2], BuildKit.r_facing(e[3])))
	bp.add(_pc("floor", Vector3(0, BuildKit.WALL_H, 0)))
	var bal := bp.snap("floor_half", Vector3(0.3, BuildKit.WALL_H, 2.9))
	check(BuildKit.vec(bal["p"]).distance_to(Vector3(0, BuildKit.WALL_H, 3)) < 0.01, "a balcony: a half floor out from the ceiling (%s)" % str(bal["p"]))
	check_eq(bp.check(bal.merged({"m": 1})), "", "held up by the wall under its edge")
	bp.add(bal.merged({"m": 1, "s": "minoa"}))
	check(int(bp.spans[bp.pieces.size() - 1]) >= 2, "carried by the wall it rests on (span %d)" % int(bp.spans[bp.pieces.size() - 1]))
	# Quarter floors beside a half: held by their neighbours, one less each.
	var qf := bp.snap("floor_quarter", Vector3(-1.0, BuildKit.WALL_H, 4.6))
	check(not qf.is_empty() and bp.check(qf.merged({"m": 1})) == "", "a quarter floor off the balcony's edge (%s)" % str(qf))
	# No wall on a quarter's 2 m edge.
	var w := bp.snap("railing", Vector3(-2.0, BuildKit.WALL_H + 0.5, 3.0))
	check(w.is_empty() or (BuildKit.vec(w["p"]).distance_to(Vector3(-2, BuildKit.WALL_H, 3)) > 0.5), "walls only on a whole cell's edge")
	var b := CosmosTown.Builder.new()
	var res := BuildKit.emit(b, _pc("floor_quarter", Vector3(1, 3.2, 1)))
	check(b.verts.size() > 0 and (res["solids"] as Array)[0] is AABB and absf(((res["solids"] as Array)[0] as AABB).size.x - 2.0) < 0.01, "a quarter floor: 2 x 2 m, solid")


func test_locked_doors() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var b: CosmosBuilds = c.builds
	b._sync_t = 1e9
	var st := CosmosStructure.new()
	st.setup(null, {"o": [0, 1000, 0], "x": [1, 0, 0], "pieces": []})
	c.world.add_child(st)
	_house(st, "door")
	st.plan.pieces.filter(func(q): return q["t"] == "door")[0]["own"] = "you"
	await _wait_built(st)
	b.structures = [st]
	b.planet = c.planets[0]
	var me := Node3D.new()
	c.world.add_child(me)
	me.global_position = st.to_global(Vector3(0, 0.05, -3.0))
	var door: Dictionary = st.plan.pieces.filter(func(q): return q["t"] == "door")[0]
	var pr := b.prompt(me)
	check(not pr.is_empty() and str(pr[0]) == "Open the door", "by the door: open it (%s)" % str(pr))
	check(b.lock_near(me) and bool(door["lk"]), "Y locks it")
	pr = b.prompt(me)
	check(not pr.is_empty() and str(pr[0]).begins_with("Locked"), "locked: it says so (%s)" % str(pr))
	b.use(str(pr[1]))
	check(not bool(door.get("o", false)), "a click doesn't open it")
	# Someone else walking into it: locked, it stops them; unlocked, they push it open.
	b.push_body(st.to_global(Vector3(0, 0.05, -2.0)), 0.5, true)
	check(not bool(door.get("o", false)), "a raider can't open a locked door")
	b.lock_near(me)
	check(not bool(door["lk"]), "Y again: unlocked")
	b.push_body(st.to_global(Vector3(0, 0.05, -2.0)), 0.5, true)
	check(bool(door.get("o", false)), "unlocked, a raider pushes it open")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(st.rec))
	check(saved["pieces"].any(func(q): return q["t"] == "door" and q.has("lk")), "the lock kept in the save")
	b.structures = []
	c.queue_free()
	await tree.process_frame


func test_wear_breaking_and_upgrades() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var b: CosmosBuilds = c.builds
	b._sync_t = 1e9
	var st := CosmosStructure.new()
	st.setup(null, {"o": [0, 1000, 0], "x": [1, 0, 0], "pieces": []})
	c.world.add_child(st)
	_house(st)
	await _wait_built(st)
	b.structures = [st]
	var wall_i := -1
	for i in st.plan.pieces.size():
		if st.plan.pieces[i]["t"] == "wall" and BuildKit.vec(st.plan.pieces[i]["p"]).x < -1.0:
			wall_i = i
	var wall: Dictionary = st.plan.pieces[wall_i]
	var full := BuildKit.hp_of("wall", 1)
	# A bolt into the wall from outside wears it.
	var a := st.to_global(Vector3(-8, 1.5, 0.3))
	check(b.bolt_hit(a, st.global_basis * Vector3.RIGHT, 10.0, 50.0), "a bolt stops on the wall")
	check(absf(BuildKit.hp_now(wall) - (full - 50.0)) < 0.5, "and wears it (%.0f of %d)" % [BuildKit.hp_now(wall), full])
	check_eq(BuildKit.wear_level(wall), 0, "a little: no cracks yet")
	b.damage(st, st.plan.pieces.find(wall), full * 0.5)
	check_eq(BuildKit.wear_level(wall), 2, "half gone: it shows")
	check(st.busy(), "its chunk built again (its look)")
	var bb := CosmosTown.Builder.new()
	BuildKit.emit(bb, wall)
	check(bb.cols[0].a < 0.95, "worn in its vertices (the shader's cracks)")
	# Upgraded in place: whole again.
	CosmosBuilds.give({"stone": 50, "marble": 50})
	check(b.upgrade(st, wall), "upgraded to marble")
	check(not wall.has("hp") and BuildKit.wear_level(wall) == 0, "an upgrade makes it whole")
	# The ceiling's held by four walls: break one - it stands; break the foundation - all falls.
	var n0 := st.plan.pieces.size()
	b.damage(st, st.plan.pieces.find(wall), 1e6)
	check_eq(st.plan.pieces.size(), n0 - 1, "a wall broken: the rest stand")
	b.damage(st, 0, 1e6)
	check(st.plan.pieces.all(func(q): return BuildKit.vec(q["p"]).x > 1.9), "the foundation broken: everything it held up falls (%d left, all on the other)" % st.plan.pieces.size())
	b.structures = []
	c.queue_free()
	await tree.process_frame


## Free building (--free-build, a sandbox): nothing costs anything, nothing needs
## holding up nor falls; the sockets and overlaps still count. Off again: the rules back.
func test_free_building() -> void:
	if CosmosGame.data == null:
		CosmosGame._fresh_data()
		await tree.process_frame
	var d: Node = CosmosGame.data
	var was: bool = BuildKit.free_build
	d.items.erase("stone")
	d.carried.erase("stone")
	BuildKit.free_build = true
	var plan := BuildPlan.new([])
	check_eq(plan.check(_pc("wall", Vector3(30, 0, 0))), "", "free: a wall on nothing goes")
	plan.add(_pc("foundation", Vector3.ZERO))
	plan.add(_pc("floor", Vector3(40, 9.6, 0)))
	check_eq(plan.check(_pc("foundation", Vector3.ZERO)), "There's one there already", "free: still one piece a socket")
	check_eq(plan.remove(0).size(), 1, "free: taking one away brings nothing else down")
	CosmosBuilds.spend({"stone": 4})
	check_eq(d.count("stone"), 0, "free: spending takes nothing (none to take)")
	BuildKit.free_build = false
	check_eq(plan.check(_pc("wall", Vector3(30, 0, 0))), "Nothing holds it up", "off again: the rules back")
	BuildKit.free_build = was


## Aiming in the game (the line of sight given): the taken sockets passed over,
## the one shown kept while the sights wobble, another taken once clearly nearer.
func test_snapping_by_line_of_sight() -> void:
	var plan := BuildPlan.new([])
	plan.add(_pc("foundation", Vector3.ZERO))
	plan.add(_pc("foundation", Vector3(4, 0, 0)))
	var west := _pc("wall", Vector3(-2, 0, 0), BuildKit.r_facing(Vector3(-1, 0, 0)))
	plan.add(west)
	var eye := Vector3(-9, 2.0, 0.3)
	var look := (Vector3(-2, 1.4, 0.2) - eye).normalized()
	var w := plan.snap("wall", Vector3(-2.1, 1.4, 0.2), 0, 3.6, eye, look)
	check(not w.is_empty() and BuildKit.vec(w["p"]).distance_to(Vector3(-2, 0, 0)) > 0.5, "looking at a wall already there: the preview goes to a free edge, not on it (%s)" % str(w.get("p")))
	var p0 := BuildKit.vec(w["p"]) if not w.is_empty() else Vector3.INF
	var same := 0
	for i in 20:   # (the sights wobbling a little: the same socket)
		var j := Vector3(sin(i * 1.7), cos(i * 2.3), sin(i * 0.9)) * 0.03
		var wj := plan.snap("wall", Vector3(-2.1, 1.4, 0.2) + j * 4.0, 0, 3.6, eye, (look + j).normalized())
		if not wj.is_empty() and BuildKit.vec(wj["p"]) == p0:
			same += 1
	check_eq(same, 20, "the sights wobbling: the preview stays put")
	var far := plan.snap("wall", Vector3(6.1, 1.4, 0.2), 0, 3.6, Vector3(13, 2.0, 0.3), (Vector3(6, 1.4, 0) - Vector3(13, 2.0, 0.3)).normalized())
	check(not far.is_empty() and BuildKit.vec(far["p"]).distance_to(Vector3(6, 0, 0)) < 0.01, "looking clearly elsewhere: it moves there (%s)" % str(far.get("p")))


## Dragging out a run of foundations on open ground (a new structure): on the
## grid of the frame where the drag began, each checked on its real ground, all
## placed into one structure - with free building too (no materials needed).
func test_drag_a_run_on_open_ground() -> void:
	var c := await _cosmos()
	c.dry_run = true
	var pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if p.shape.kind == "rocky":
			pl = p
			break
	var d := Vector3(-0.5, 0.7, 0.3).normalized()
	var x := d.cross(Vector3.UP).normalized()
	var b := c.builds
	b._sync_t = 1e9
	b.planet = pl
	b.structures = []
	var was: bool = BuildKit.free_build
	BuildKit.free_build = true
	CosmosBuilds.piece = "foundation"
	var top := 0.0
	var fr := Transform3D(Basis(x, d, x.cross(d)), d * (pl.radius + pl.shape.height(d)))
	top = b._new_top(Vector3.ZERO, fr, "sq")
	fr.origin += d * top
	b.aim_frame = fr
	b._drag_frame = fr
	b._drag_st = null
	b._drag_from = _pc("foundation", Vector3.ZERO)
	b._update_run({"t": "foundation", "p": [8.0, 0.0, 4.0], "r": 0})
	check_eq(b._run.size(), 6, "a 3 x 2 run of foundations")
	var oks := b._run.filter(func(it): return it[1]).size()
	check(oks >= 5, "free building: they fit, no materials needed (%d of 6)" % oks)
	var n := b.place_run()
	check(n == oks and b.structures.size() == 1 and (b.structures[0] as CosmosStructure).plan.pieces.size() == n, "placed: %d, all in one structure" % n)
	# In a town (its ground's no place to build - but free building: anywhere), the run fits there too.
	var town_pl: CosmosPlanet = null
	for p: CosmosPlanet in c.planets:
		if not p.towns.is_empty():
			town_pl = p
			break
	if town_pl:
		b.planet = town_pl
		var td: Vector3 = (town_pl.towns[0]["dir"] as Vector3).normalized()
		var tx := td.cross(Vector3.UP).normalized()
		var tf := Transform3D(Basis(tx, td, tx.cross(td)), td * (town_pl.radius + town_pl.shape.height(td)))
		tf.origin += td * b._new_top(Vector3.ZERO, tf, "sq")
		check(town_pl.shape.cleared(td), "(a town's ground)")
		b.aim_frame = tf
		b._drag_frame = tf
		b._drag_st = null
		b._drag_from = _pc("foundation", Vector3.ZERO)
		b._update_run({"t": "foundation", "p": [4.0, 0.0, 0.0], "r": 0})
		check(b._run.size() == 2 and b._run.all(func(it): return it[1]), "free building: a run in a town fits (%s)" % str(b._run.map(func(it): return it[1])))
		BuildKit.free_build = false
		b._update_run({"t": "foundation", "p": [4.0, 0.0, 0.0], "r": 0})
		check(b._run.all(func(it): return not it[1]), "without it: not in a town")
	BuildKit.free_build = was
	b._clear_run()
	c.queue_free()
	await tree.process_frame
