extends TestCase
## Editing what's solid while the game runs (SolidsEdit, the Live Editor's
## Collision tab): a town's blocks and a station's turned boxes read, moved,
## added, deleted - the walker's push and the camera's line meet them at once -
## and the edit kept (LiveEdits) and put back on the same place built again.

const TAB := "res://scripts/world/live/tabs/collision_tab.gd"

var _saved := {}
var _dirty := false


func setup() -> void:
	LiveEdits.load_all()
	_saved = LiveEdits.data.duplicate(true)
	_dirty = LiveEdits.dirty


func teardown() -> void:
	LiveEdits.data = _saved
	LiveEdits._index()
	LiveEdits.dirty = _dirty


func _town(seed := 7) -> CosmosTown:
	var t := CosmosTown.new()
	t.setup(null, {"kind": "village", "seed": seed, "empire": "minoa", "name": "Test%d" % seed, "r": 130.0})
	tree.root.add_child(t)
	t.want(true)
	return t


func _wait_town(t: CosmosTown) -> void:
	var t0 := Time.get_ticks_msec()
	while not t.poll() and Time.get_ticks_msec() - t0 < 15000:
		await tree.process_frame


## The shape holding (town-local) point `p` (-1: none).
func _at(shapes: Array, p: Vector3) -> int:
	for i in shapes.size():
		if SolidsEdit.distance(shapes[i], p) == 0.0:
			return i
	return -1


func _blocked(t: CosmosSolids, feet: Vector3) -> bool:
	return t.push(feet, 0.4) != Vector3.ZERO


func test_town_solids_edited_live_and_kept() -> void:
	var t := _town()
	await _wait_town(t)
	check(t.built, "the town built")
	check(SolidsEdit.owner_of(t.get_child(0)) == t, "a part of it picked: the town holds its solids")
	check(load(TAB).handles(t.get_child(0)), "the Collision tab takes it")
	var key := str(LiveEdits.anchor_of(t.get_child(0))[1])
	check_eq(key, "town/minoa/village/7", "its edits kept for this town (its seed)")
	var shapes := SolidsEdit.boxes(t)
	check(shapes.size() > 50, "its blocks read (%d)" % shapes.size())
	var port: Vector3 = CosmosTown.layout("village")["port"]
	var post_a := port + Vector3(-32, 0, 32)   # (two of the landing field's corner posts)
	var post_b := port + Vector3(32, 0, 32)
	var feet := Vector3(0, 0.1, 0)
	var ia := _at(shapes, post_a + Vector3(0, 1, 0))
	var ib := _at(shapes, post_b + Vector3(0, 1, 0))
	check(ia >= 0 and ib >= 0, "the posts are among them")
	check(_blocked(t, post_a + feet) and _blocked(t, post_b + feet), "both posts in the way")
	# Move one 6 m along x, delete the other, add a box in the field's middle.
	var moved := post_a + Vector3(6, 0, 0)
	var xf: Transform3D = shapes[ia]["xf"]
	xf.origin += Vector3(6, 0, 0)
	shapes[ia]["xf"] = xf
	shapes.remove_at(ib)
	shapes.append(SolidsEdit.make(port + Vector3(0, 1, 0), Vector3(1, 1, 1)))
	SolidsEdit.set_boxes(t, shapes)
	check(not _blocked(t, post_a + feet), "the moved post's old place: clear")
	check(_blocked(t, moved + feet), "its new place: in the way")
	check(not _blocked(t, post_b + feet), "the deleted post: gone")
	check(_blocked(t, port + feet), "the added box: in the way")
	var g := t.to_global(moved + Vector3(0, 1, -4))
	check(t.cam_hit(g, Vector3(0, 0, 1), 8.0) < 4.0, "the camera's line meets the moved post")
	check(t.cam_hit(t.to_global(post_a + Vector3(0, 1, -4)), Vector3(0, 0, 1), 8.0) == INF, "not its old place")
	# A turned box (a prism in the town's grid).
	var s := SolidsEdit.boxes(t)
	s.append(SolidsEdit.make(port + Vector3(10, 1, 10), Vector3(3, 1, 0.3), Basis(Vector3.UP, PI * 0.25)))
	SolidsEdit.set_boxes(t, s)
	var along := port + Vector3(10, 0.1, 10) + Basis(Vector3.UP, PI * 0.25) * Vector3(2.5, 0, 0)
	check(_blocked(t, along), "a box turned 45 degrees: in the way along its length")
	check(not _blocked(t, port + Vector3(12.5, 0.1, 10)), "not where it would be unturned")
	var back := SolidsEdit.boxes(t)
	check(absf((back[back.size() - 1]["xf"] as Transform3D).basis.get_euler().y - PI * 0.25) < 0.01, "read back with its turn")
	# Kept: the edit as a difference, put back on the same town built again.
	var rec := SolidsEdit.record(t)
	check_eq([rec["del"].size(), rec["mod"].size(), rec["add"].size()], [1, 1, 2], "the record: one deleted, one moved, two added")
	rec["path"] = "."
	LiveEdits.data[key] = {"collision": JSON.parse_string(JSON.stringify(rec))}   # (as saved and loaded)
	var t2 := _town()
	await _wait_town(t2)
	check(not _blocked(t2, post_a + feet) and _blocked(t2, moved + feet), "built again: the post where it was moved")
	check(not _blocked(t2, post_b + feet), "the deleted one still gone")
	check(_blocked(t2, port + feet) and _blocked(t2, along), "the added ones there")
	var n := (t2._solids as Array).size()
	load(TAB).apply_edit(t2, LiveEdits.data[key]["collision"])
	LiveEdits.apply(t2, key)
	check_eq((t2._solids as Array).size(), n, "put back again (LiveEdits' tries): the same, not twice")
	# Another town (another seed): its own layout - not this one's edit.
	var t3 := _town(8)
	await _wait_town(t3)
	check(_blocked(t3, post_a + feet) and _blocked(t3, post_b + feet), "another town keeps its posts")
	# Back to as built.
	SolidsEdit.revert(t2)
	check(_blocked(t2, post_a + feet) and _blocked(t2, post_b + feet) and not _blocked(t2, port + feet), "reverted: as built")
	for x in [t, t2, t3]:
		x.free()


func test_station_boxes() -> void:
	var st := CosmosStation.new()
	var rec := {"id": "test:solids", "name": "Test solids", "empire": "athens", "economy": "trade", "health": 100.0}
	st.setup(rec)
	tree.root.add_child(st)
	check_eq(str(st.get_meta("edit_key")), "station/athens/test:solids", "its edits kept for this station (its id)")
	var shapes := SolidsEdit.boxes(st)
	check(shapes.size() > 60, "its parts read (%d)" % shapes.size())
	check(shapes.any(func(s): return s["kind"] == "obox") and shapes.any(func(s): return s["kind"] == "cyl"), "boxes and cylinders")
	check_eq(SolidsEdit.rotation_of(st), "full", "turned any way")
	# A box turned 45 degrees about z, far over the station.
	var up := Vector3(0, 3000, 0)
	var b := Basis(Vector3(0, 0, 1), PI * 0.25)
	shapes.append(SolidsEdit.make(up, Vector3(10, 2, 10), b))
	# One of its parts moved up there too.
	var xf: Transform3D = shapes[0]["xf"]
	xf.origin = Vector3(0, 4000, 0)
	shapes[0]["xf"] = xf
	SolidsEdit.set_boxes(st, shapes)
	var inside := up + b * Vector3(9, 0, 0)   # (inside it turned; over it unturned)
	check(st.push_out(st.to_global(inside), 0.5) != Vector3.ZERO, "the turned box: in the way along its turn")
	check(st.push_out(st.to_global(up + Vector3(0, 6, 0)), 0.5) == Vector3.ZERO, "not where it would be unturned")
	check(st.cam_hit(st.to_global(up + Vector3(0, 0, -50)), st.global_basis * Vector3(0, 0, 1), 100.0) < 50.0, "the camera's line meets it")
	check(st.push_out(st.to_global(Vector3(0, 4000, 0)), 0.5) != Vector3.ZERO, "the moved part: in the way up there")
	# Kept and put back on the same station built again.
	var r := SolidsEdit.record(st)
	r["path"] = "."
	LiveEdits.data["station/athens/test:solids"] = {"collision": JSON.parse_string(JSON.stringify(r))}
	var st2 := CosmosStation.new()
	st2.setup(rec)
	tree.root.add_child(st2)
	check(st2.push_out(st2.to_global(inside), 0.5) != Vector3.ZERO and st2.push_out(st2.to_global(Vector3(0, 4000, 0)), 0.5) != Vector3.ZERO,
		"built again: its edits back")
	check_eq((st2._solids as Array).size(), (st._solids as Array).size(), "the same number of parts")
	st.free()
	st2.free()


func test_hangar_and_dungeon() -> void:
	# A port's camera boxes and footprints: one box where both are the same.
	var h := CosmosHangar.new()
	h._boxes = [[Vector3(5, 1, 5), Vector3(1, 1, 1)]]
	h._blocks = [[4.0, 4.0, 6.0, 6.0], [10.0, 10.0, 11.0, 11.0]]
	var s := SolidsEdit.boxes(h)
	check_eq(s.map(func(x): return x["use"]), ["both", "walk"], "a box both, a footprint for the feet")
	var xf: Transform3D = s[1]["xf"]
	xf.origin += Vector3(2, 0, 0)
	s[1]["xf"] = xf
	s[0]["use"] = "cam"
	SolidsEdit.set_boxes(h, s)
	check_eq(h._blocks, [[12.0, 10.0, 13.0, 11.0]], "the footprint moved, the camera-only box off the feet's list")
	check_eq(h._boxes.size(), 1, "the camera's box kept")
	check_eq(h._cells_n, -1, "its cells made again")
	h.free()
	# A dungeon's blocks: axis-aligned, in its grid.
	var d := CosmosDungeon.new()
	d._solids = [AABB(Vector3(0, 0, 0), Vector3(2, 3, 2))]
	d._grid = CosmosSolids.grid_of(d._solids)
	check(d.push(Vector3(1, 0.1, 1), 0.4) != Vector3.ZERO, "its block in the way")
	var ds := SolidsEdit.boxes(d)
	var dx: Transform3D = ds[0]["xf"]
	dx.origin += Vector3(20, 0, 0)
	ds[0]["xf"] = dx
	SolidsEdit.set_boxes(d, ds)
	check(d.push(Vector3(1, 0.1, 1), 0.4) == Vector3.ZERO and d.push(Vector3(21, 0.1, 1), 0.4) != Vector3.ZERO, "moved, in its grid")
	d.free()


## The tab itself, bound to a stand-in for the Live Editor: a click in the world
## picks a post, its centre edited moves it (the walker meets it there), kept.
func test_collision_tab() -> void:
	var t := _town()
	await _wait_town(t)
	var fake := GDScript.new()
	fake.source_code = """extends Node3D
var selected: Node
var anchor: Node
var key := ""
var cosmos: Node
var said := ""
var edits := 0
var cam: Camera3D
func say(t: String) -> void:
	said = t
func edited(_s := "") -> void:
	edits += 1
func camera() -> Camera3D:
	return cam
func pick_ray(_p: Vector2) -> Array:
	return [Vector3.ZERO, Vector3.FORWARD]
"""
	fake.reload()
	var ed: Node3D = fake.new()
	tree.root.add_child(ed)
	var cam := Camera3D.new()
	ed.add_child(cam)
	var port: Vector3 = CosmosTown.layout("village")["port"]
	var post := port + Vector3(-32, 0, 32)
	cam.global_position = t.to_global(post + Vector3(0, 1.5, -10))
	ed.cam = cam
	ed.selected = t.get_child(0)
	var a := LiveEdits.anchor_of(ed.selected)
	ed.anchor = a[0]
	ed.key = a[1]
	var tab: VBoxContainer = load(TAB).new()
	tree.root.add_child(tab)
	tab.bind(ed)
	tab.live_process(0.3)
	check(tab._list.item_count > 0, "the boxes near the camera listed (%d)" % tab._list.item_count)
	check(tab._im.get_surface_count() == 1, "drawn as lines")
	check(tab.pick_in_world(cam.global_position, (t.to_global(post + Vector3(0, 1, 0)) - cam.global_position).normalized()), "a click on the post: taken")
	var i: int = tab._sel
	check(i >= 0 and SolidsEdit.distance(tab._shapes[i], post + Vector3(0, 1, 0)) == 0.0, "the post selected")
	var c: Vector3 = (tab._shapes[i]["xf"] as Transform3D).origin
	tab._change(i, "centre", c + Vector3(0, 0, -5))
	check(not _blocked(t, post + Vector3(0, 0.1, 0)) and _blocked(t, post + Vector3(0, 0.1, -5)), "moved: the walker meets it there at once")
	var sec: Dictionary = LiveEdits.data.get(ed.key, {}).get("collision", {})
	check(sec.get("mod", []).size() == 1 and sec.get("path") == ".", "kept as the edit's record")
	check(ed.edits > 0, "the editor told")
	var n0: int = tab._shapes.size()
	tab._duplicate()
	tab._delete()
	tab._add()
	check_eq(tab._shapes.size(), n0 + 1, "copied, deleted, added")
	tab._revert()
	check(_blocked(t, post + Vector3(0, 0.1, 0)) and not LiveEdits.data.get(ed.key, {}).has("collision"), "reverted: as built, its edit forgotten")
	tab.unbind()
	tab.free()
	ed.free()
	t.free()
