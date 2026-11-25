extends Node
## More of the mesh editor's edit-mode tools (a node of the editor, `ed`):
## - Duplicate (Shift+D): the selected faces copied (their points too) - the copy selected and moved.
## - Merge by distance (Alt+M): the selected points (all, if none) closer than `merge_dist` made one;
##   Auto merge: after each move / turn / scale, the points it moved onto others welded to them.
## - Inset (I): a ring of new faces inside the selected region's border, its width by the mouse
##   (or typed); click keeps, right-click / Esc cancels.
## - Loop cut (Ctrl+R): the ring of quads across the edge under the mouse shown; a click cuts a new
##   edge loop through it, then the mouse slides it along the ring; click keeps it (right-click /
##   Esc: kept in the middle).
## - Select loop / ring (Alt+click an edge; the buttons from the selected edges): the edge loop
##   straight on through four-way points, or the edges across a ring of quads; in face mode the
##   faces of the ring, in vertex mode the loop's points.
## The geometry (static, on an EditMesh) is plain data; the rest drives the editor's transform
## (xf: "step" / "on_cancel" / "name" - mesh_editor.gd calls them) and its undo (one step each).

const EditMesh := preload("res://scripts/editor/mesh/edit_mesh.gd")
const DEFAULT_DIST := 0.0001

var ed: Control
## Merge by distance's threshold (metres, the part's own space).
var merge_dist := DEFAULT_DIST
## Points a transform moved onto others welded to them when it ends.
var auto_merge := false
## The loop cut is waiting for a click (the ring under the mouse shown).
var cutting := false
var _ring := {}
var _alt_at := Vector2(-1, -1)
var _auto_btn: Button
var _dist_spin: SpinBox


func setup(editor: Control) -> void:
	ed = editor
	name = "MeshOps"


# --- the geometry (an EditMesh) ----------------------------------------------------

## Copies of the faces flagged in `tsel` (whole faces): their vertices copied (every attribute)
## onto new points at the same places, the copies' faces new ids. Returns the new points.
static func duplicate_faces(em, tsel: PackedByteArray) -> PackedInt32Array:
	var n0: int = em.points.size()
	var pts: PackedVector3Array = em.points
	var np := PackedInt32Array()
	np.resize(n0)
	np.fill(-1)
	var out := PackedInt32Array()
	var st: Array = em._starts(tsel)
	var next: int = em.face_n
	var fmap := {}
	for si in em.surfs.size():
		var starts: PackedInt32Array = st[si]
		if starts.is_empty():
			continue
		var s = em.surfs[si]
		var idx: PackedInt32Array = s.idx
		var face: PackedInt32Array = s.face
		var vm := {}
		for i0 in starts:
			for k in 3:
				var v: int = idx[i0 + k]
				if not vm.has(v):
					var p: int = s.vp[v]
					if np[p] < 0:
						np[p] = pts.size()
						out.append(pts.size())
						pts.append(pts[p])
					vm[v] = s.copy_vertex(v, np[p])
				idx.append(vm[v])
			var f: int = face[i0 / 3] if i0 / 3 < face.size() else -1
			if not fmap.has(f):
				fmap[f] = next
				next += 1
			face.append(fmap[f])
		s.idx = idx
		s.face = face
	em.points = pts
	em.derive()
	return out


## Point -> the point it becomes (`to`, itself if it stays): the points of `query` within `dist`
## of a point of `targets` (both empty: all points) joined, through each other too. A group's
## point is its lowest (`fixed` flags a point that stays where it is - one in a group leads it).
## Returns {"to": PackedInt32Array, "at": {point: where}, "removed": int}.
static func close_points(points: PackedVector3Array, query: PackedInt32Array, targets: PackedInt32Array, dist: float, fixed := PackedByteArray()) -> Dictionary:
	var n := points.size()
	var to := PackedInt32Array()
	to.resize(n)
	for i in n:
		to[i] = i
	if dist <= 0.0 or n < 2:
		return {"to": to, "at": {}, "removed": 0}
	if query.is_empty():
		query = PackedInt32Array(range(n))
	if targets.is_empty():
		targets = query
	var inv := 1.0 / dist
	var grid := {}
	for p in targets:
		var c := Vector3i((points[p] * inv).floor())
		if grid.has(c):
			(grid[c] as Array).append(p)
		else:
			grid[c] = [p]
	var d2 := dist * dist
	var parent := to.duplicate()
	var touched := {}
	var lead := func(a: int, b: int) -> bool:   # (a leads b: fixed first, else the lower)
		var fa := not fixed.is_empty() and fixed[a] == 1
		var fb := not fixed.is_empty() and fixed[b] == 1
		return fa and not fb or (fa == fb and a < b)
	for q in query:
		var c := Vector3i((points[q] * inv).floor())
		for x in range(-1, 2):
			for y in range(-1, 2):
				for z in range(-1, 2):
					var cell = grid.get(c + Vector3i(x, y, z))
					if cell == null:
						continue
					for p: int in cell:
						if p == q or points[p].distance_squared_to(points[q]) > d2:
							continue
						var ra := _find(parent, q)
						var rb := _find(parent, p)
						if ra == rb:
							continue
						if lead.call(ra, rb):
							parent[rb] = ra
						else:
							parent[ra] = rb
						touched[p] = true
						touched[q] = true
	var removed := 0
	var sum := {}
	var cnt := {}
	for p in touched:
		var r := _find(parent, p)
		to[p] = r
		if r != p:
			removed += 1
		sum[r] = sum.get(r, Vector3.ZERO) + points[p]
		cnt[r] = cnt.get(r, 0) + 1
	var at := {}
	for r in sum:
		at[r] = points[r] if not fixed.is_empty() and fixed[r] == 1 else sum[r] / float(cnt[r])
	return {"to": to, "at": at, "removed": removed}


static func _find(parent: PackedInt32Array, p: int) -> int:
	var r := p
	while parent[r] != r:
		r = parent[r]
	while parent[p] != r:
		var nx := parent[p]
		parent[p] = r
		p = nx
	return r


## The points welded as `close` (close_points) says: each made the point it goes to (moved to
## its place), triangles left with two corners on one point dropped, the points nothing uses
## dropped. Returns old point -> new (-1: gone).
static func weld(em, close: Dictionary) -> PackedInt32Array:
	var to: PackedInt32Array = close["to"]
	var at: Dictionary = close["at"]
	var pts: PackedVector3Array = em.points
	for r in at:
		pts[r] = at[r]
	em.points = pts
	var touched := {}   # points merged into (a face on them may now double another)
	for p in to.size():
		if to[p] != p:
			touched[to[p]] = true
	var seen := {}      # a triangle's points (sorted) -> kept already
	for s in em.surfs:
		var vp: PackedInt32Array = s.vp
		for v in vp.size():
			vp[v] = to[vp[v]]
		s.vp = vp
		s.sync(pts, PackedInt32Array())
		s.drop_degenerate()
		# (faces welded onto each other - a copy merged back - kept once)
		var kill := {}
		for i in range(0, s.idx.size() - 2, 3):
			var t := [s.vp[s.idx[i]], s.vp[s.idx[i + 1]], s.vp[s.idx[i + 2]]]
			if not (touched.has(t[0]) or touched.has(t[1]) or touched.has(t[2])):
				continue
			t.sort()
			var key := Vector3i(t[0], t[1], t[2])
			if seen.has(key):
				kill[i] = true
			else:
				seen[key] = true
		if not kill.is_empty():
			s.drop_tris(kill)
		s.compact()
	var map := _compact_map(em)
	em.compact()
	em.unused = false
	em.derive()
	var out := PackedInt32Array()   # (a point merged: the number of the one it went into)
	out.resize(map.size())
	for p in map.size():
		out[p] = map[to[p]]
	return out


## What EditMesh.compact() will renumber the points to (old -> new, -1: dropped) - the
## surfaces' unused vertices dropped first (as it does).
static func _compact_map(em) -> PackedInt32Array:
	var n: int = em.points.size()
	var used := PackedByteArray()
	used.resize(n)
	for s in em.surfs:
		s.compact()
		for p in s.vp:
			used[p] = 1
	var map := PackedInt32Array()
	map.resize(n)
	var k := 0
	for p in n:
		if used[p]:
			map[p] = k
			k += 1
		else:
			map[p] = -1
	return map


## Inset: the faces flagged in `tsel` (a region) moved onto copies of their points, a ring of
## quads along the region's border joining them to it (as an extrude whose top isn't lifted).
## Returns {"ids": the border points' copies, "orig": their places, "dirs": the way each goes in
## (along the faces, as far as the inset is wide - a corner further, its sides keeping the width),
## "inner": all the region's points (new numbers), "ring": the border's points} - or {} if none.
static func inset_region(em, tsel: PackedByteArray) -> Dictionary:
	var n0: int = em.points.size()
	var pts: PackedVector3Array = em.points
	var np := PackedInt32Array()
	np.resize(n0)
	np.fill(-1)
	var border := {}
	var side := {}   # edge key -> [a, b, c]: a -> b along the region's triangle, c its third corner
	for t in mini(tsel.size(), em.tri_count()):
		if not tsel[t]:
			continue
		for k in 3:
			var a: int = em.tris[t * 3 + k]
			var b: int = em.tris[t * 3 + (k + 1) % 3]
			var key := mini(a, b) * n0 + maxi(a, b)
			border[key] = border.get(key, 0) + 1
			side[key] = [a, b, em.tris[t * 3 + (k + 2) % 3]]
			if np[a] < 0:
				np[a] = pts.size()
				pts.append(pts[a])
	if border.is_empty():
		return {}
	# the way in at each border point: the sides' inward directions met
	var ins := {}   # point -> [inward unit vectors]
	for key in border:
		if border[key] != 1:
			continue
		var s: Array = side[key]
		var pa: Vector3 = pts[s[0]]
		var pb: Vector3 = pts[s[1]]
		var pc: Vector3 = pts[s[2]]
		var e := (pb - pa).normalized()
		var w := pc - pa
		var u := (w - e * w.dot(e)).normalized()
		for p in [s[0], s[1]]:
			if ins.has(p):
				(ins[p] as Array).append(u)
			else:
				ins[p] = [u]
	if ins.is_empty():
		return {}   # (a closed region - nothing to inset from)
	em.points = pts
	var st: Array = em._starts(tsel)
	var next: int = em.face_n
	for si in em.surfs.size():
		if not (st[si] as PackedInt32Array).is_empty():
			next = em.surfs[si].extrude(st[si], np, border, n0, next)
			em.surfs[si].recalc_normals()
	var map := _compact_map(em)   # (the region's inside points: only the copies use them now)
	em.compact()
	em.derive()
	var ids := PackedInt32Array()
	var orig := PackedVector3Array()
	var dirs := PackedVector3Array()
	var ring := PackedInt32Array()
	for p in ins:
		var us: Array = ins[p]
		var m := Vector3.ZERO
		for u: Vector3 in us:
			m += u
		var d: Vector3 = us[0]
		if m.length() > 1e-6:
			var mn := m.normalized()
			var c := 1.0
			for u: Vector3 in us:
				c = minf(c, mn.dot(u))
			d = mn / maxf(c, 0.25)
		ids.append(map[np[p]])
		orig.append(em.points[map[np[p]]])
		dirs.append(d)
		if map[p] >= 0:
			ring.append(map[p])
	var inner := PackedInt32Array()
	for p in n0:
		if np[p] >= 0 and map[np[p]] >= 0:
			inner.append(map[np[p]])
	return {"ids": ids, "orig": orig, "dirs": dirs, "inner": inner, "ring": ring}


## The faces (n-gons) along edge `e` (a triangle of each).
static func _faces_on(em, e: int) -> Array:
	var out := {}
	for t in em.edge_tri_list(e):
		if not out.has(em.tri_face[t]):
			out[em.tri_face[t]] = t
	return out.values()


## From edge a -> b into the face of triangle `t`: on across quads to their opposite sides.
## [[a, b] of each side crossed, in order], [a triangle of each quad crossed], closed (back at `e0`).
static func _walk(em, a: int, b: int, t: int, e0: int, seen: Dictionary) -> Array:
	var sides := []
	var quads := PackedInt32Array()
	var closed := false
	while true:
		var f: int = em.tri_face[t]
		if seen.has(f):
			break
		var lp: PackedInt32Array = em.poly_loop(t)
		if lp.size() != 4:
			break
		var i := lp.find(a)
		if i < 0:
			break
		var na := -1
		var nb := -1
		if lp[(i + 1) % 4] == b:
			na = lp[(i + 3) % 4]
			nb = lp[(i + 2) % 4]
		elif lp[(i + 3) % 4] == b:
			na = lp[(i + 1) % 4]
			nb = lp[(i + 2) % 4]
		else:
			break
		var ne: int = em.edge(na, nb)
		if ne < 0:
			break
		seen[f] = true
		quads.append(t)
		if ne == e0:
			closed = true
			break
		sides.append([na, nb])
		var nt := -1
		var lst: PackedInt32Array = em.edge_tri_list(ne)
		if lst.size() != 2 and _faces_on(em, ne).size() != 2:
			break
		for u in lst:
			if em.tri_face[u] != f:
				nt = u
				break
		if nt < 0:
			break
		a = na
		b = nb
		t = nt
	return [sides, quads, closed]


## The ring of quads across edge a -> b: {"sides": [[a, b]...] - the edges it crosses, each a
## the same side as the first's a; "quads": a triangle of each quad between side k and k + 1
## (closed: and the last back to the first); "closed"}. Stops at a face not a quad, an open
## edge or a quad already crossed.
static func ring(em, a: int, b: int) -> Dictionary:
	var e0: int = em.edge(a, b)
	if e0 < 0:
		return {"sides": [], "quads": PackedInt32Array(), "closed": false}
	var faces := _faces_on(em, e0)
	var seen := {}
	var fwd: Array = _walk(em, a, b, faces[0], e0, seen) if faces.size() > 0 else [[], PackedInt32Array(), false]
	if fwd[2]:
		return {"sides": [[a, b]] + fwd[0], "quads": fwd[1], "closed": true}
	var back: Array = _walk(em, a, b, faces[1], e0, seen) if faces.size() == 2 else [[], PackedInt32Array(), false]
	var sides: Array = (back[0] as Array).duplicate()
	sides.reverse()
	var quads: PackedInt32Array = back[1]
	quads.reverse()
	sides.append([a, b])
	sides.append_array(fwd[0])
	quads.append_array(fwd[1])
	return {"sides": sides, "quads": quads, "closed": false}


## The knife chain (EditMesh.knife_apply) of a loop cut through ring `r`, `f` of the way from
## each side's a to its b.
static func ring_chain(em, r: Dictionary, f := 0.5) -> Dictionary:
	var nodes := []
	for s in r["sides"]:
		var e: int = em.edge(s[0], s[1])
		nodes.append(em.node_on_edge(e, f if em.edges[e * 2] == s[0] else 1.0 - f))
	if r["closed"] and not nodes.is_empty():
		nodes.append(nodes[0])
	return {"nodes": nodes, "segs": PackedInt32Array(r["quads"])}


## A shown edge (between faces, not a face's diagonal).
static func _shown(em, e: int) -> bool:
	return e >= 0 and not em.edge_inner[e]


## The edge after `e` at its point `p` going straight on: the one of the four there that
## shares no face with it (an open edge: the next open one); -1 at a pole or an end.
static func _next_in_loop(em, e: int, p: int) -> int:
	var fe := {}
	for t in em.edge_tri_list(e):
		fe[em.tri_face[t]] = true
	var shown := []
	for k in range(em.adj_start[p], em.adj_start[p + 1]):
		var e2: int = em.edge(p, em.adj[k])
		if e2 != e and _shown(em, e2):
			shown.append(e2)
	if fe.size() == 1:   # (an open edge: along the border)
		var open := []
		for e2 in shown:
			if _faces_on(em, e2).size() == 1:
				open.append(e2)
		return open[0] if open.size() == 1 else -1
	if shown.size() != 3:
		return -1
	var out := -1
	for e2 in shown:
		var shares := false
		for t in em.edge_tri_list(e2):
			if fe.has(em.tri_face[t]):
				shares = true
		if not shares:
			if out >= 0:
				return -1
			out = e2
	return out


## Edge `e0`'s loop: on from both its ends while the way goes straight on (edges, it first).
static func edge_loop(em, e0: int) -> PackedInt32Array:
	var out := PackedInt32Array([e0])
	var seen := {e0: true}
	for end in 2:
		var e := e0
		var p: int = em.edges[e0 * 2 + end]
		while true:
			var nx := _next_in_loop(em, e, p)
			if nx < 0 or seen.has(nx):
				break
			seen[nx] = true
			out.append(nx)
			p = em.edges[nx * 2] if em.edges[nx * 2 + 1] == p else em.edges[nx * 2 + 1]
			e = nx
		if end == 0 and out.size() > 1 and _next_in_loop(em, e, p) == e0:
			break   # (round: closed)
	return out


## Edge `e`'s ring: the edges across the quads either side of it, it too.
static func edge_ring(em, e: int) -> PackedInt32Array:
	var r := ring(em, em.edges[e * 2], em.edges[e * 2 + 1])
	var out := PackedInt32Array()
	for s in r["sides"]:
		out.append(em.edge(s[0], s[1]))
	return out


# --- the editor -------------------------------------------------------------------

## The new tools' buttons (the EDIT MESH panel): a row of icons, and Merge by distance's
## threshold with Auto merge.
func build_panel(box: Control) -> void:
	var row := HFlowContainer.new()
	row.name = "MeshOpsRow"
	row.add_theme_constant_override("h_separation", 2)
	row.add_theme_constant_override("v_separation", 2)
	for it in items():
		row.add_child(_icon_btn(it[0], it[1], it[2], it[3], it[4]))
	_auto_btn = _icon_btn("m_auto_merge", "Auto merge", "", "After each move, turn or scale, the points it put within the merge distance of another\npoint are welded to it (the other stays where it is). One undo step with the move.", func(): set_auto_merge(not auto_merge))
	_auto_btn.toggle_mode = true
	_auto_btn.button_pressed = auto_merge
	row.add_child(_auto_btn)
	_dist_spin = SpinBox.new()
	_dist_spin.name = "MergeDistance"
	_dist_spin.min_value = 0.000001
	_dist_spin.max_value = 10.0
	_dist_spin.step = 0.000001
	_dist_spin.value = merge_dist
	_dist_spin.custom_minimum_size.x = 86
	_dist_spin.tooltip_text = EditorIcons.tip("Merge by distance: distance", "", "Points closer than this (metres, in the part's own space) are made one by Merge by distance\nand by Auto merge.")
	_dist_spin.value_changed.connect(func(v): merge_dist = v)
	row.add_child(_dist_spin)
	box.add_child(row)


func _icon_btn(icon: String, title: String, keys: String, help: String, cb: Callable) -> Button:
	var b := Button.new()
	b.name = "Op_" + title.validate_node_name()
	b.focus_mode = Control.FOCUS_NONE
	b.icon = EditorIcons.get_icon(icon)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(32, 30)
	b.tooltip_text = EditorIcons.tip(title, keys, help)
	IconAnim.attach(b, icon)
	b.pressed.connect(func():
		if ed.em == null:
			ed.enter_edit(true)
		if ed.em != null:
			cb.call())
	return b


## [icon, title, keys, help, action] of each tool (the panel row and the right-click menu).
func items() -> Array:
	return [
		["m_duplicate_mesh", "Duplicate selection", "Shift+D", "The selected faces copied, their points too, then moved with the mouse (click keeps it where it is;\nthe copy stays even if the move is cancelled). Points and edges alone copy nothing: the mesh is faces.", duplicate_selection],
		["m_inset", "Inset", "I", "A ring of new faces inside the selected faces' border (the selection inset as one region):\nthe mouse towards the middle makes it wider, or type the width (metres); click keeps it,\nright-click / Esc cancels.", begin_inset],
		["m_loop_cut", "Loop cut", "Ctrl+R", "A new edge loop round a ring of quads: point at an edge to see the ring across it, click to cut,\nthen slide it along with the mouse and click to keep it (right-click / Esc: kept in the middle).", begin_loopcut],
		["m_sel_loop", "Select loop", "Alt+click", "The selected edges' loops: on straight through each four-way point to a pole or an open end\n(Alt+click an edge: its loop; Shift+Alt+click adds; in face mode the ring of quads, in vertex mode its points).", select_loops],
		["m_sel_ring", "Select ring", "", "The edges across the ring of quads either side of each selected edge.", select_rings],
		["m_merge_dist", "Merge by distance", "Alt+M", "The selected points (all, if none are) closer to each other than the distance beside it\nmade one - each group at its middle. Says how many went.", func(): merge_by_distance()],
	]


## The right-click menu's group of them (in edit mode).
func menu_items() -> Array:
	var out := []
	for it in items():
		out.append([it[0], it[1], it[2], it[3].split("\n")[0], it[4], true])
	out.append(["m_auto_merge", "Auto merge " + ("off" if auto_merge else "on"), "", "Points moved onto others are welded to them when the move ends.", func(): set_auto_merge(not auto_merge), true])
	return out


func set_auto_merge(on: bool) -> void:
	auto_merge = on
	if _auto_btn:
		_auto_btn.set_pressed_no_signal(on)
	ed._say("Auto merge " + ("on: points moved within %s m of another are welded to it." % _fmt(merge_dist) if on else "off."))


static func _fmt(v: float) -> String:
	return String.num(v, 6).rstrip("0").rstrip(".") if v < 1.0 else String.num(v, 3)


## The selection made points `pts` and what they make up (faces in face mode and Auto).
func _select_points(pts: PackedInt32Array) -> void:
	ed._resize_sel()
	var sp: PackedByteArray = ed.sel_p
	sp.fill(0)
	for p in pts:
		sp[p] = 1
	ed.sel_p = sp
	ed.sel_e.fill(0)
	ed.sel_t.fill(0)
	ed.sel_pa.fill(0)
	var keep: int = ed.sel_kind
	ed.sel_kind = 0
	ed._derive_sel()
	if keep == 2:
		ed.sel_kind = 2
		ed._derive_sel()
	elif keep == 3:
		ed.sel_kind = 3
		ed.sel_e.fill(0)
		ed.sel_pa.fill(0)
		ed._derive_sel()
	ed.sel_kind = keep


## The selection after points were renumbered (`map`: old -> new, -1 gone).
func _remap_selection(map: PackedInt32Array, old: PackedByteArray) -> void:
	var keep := PackedInt32Array()
	var seen := {}
	for p in mini(old.size(), map.size()):
		if old[p] and map[p] >= 0 and not seen.has(map[p]):
			seen[map[p]] = true
			keep.append(map[p])
	_select_points(keep)


## The whole faces the selected points make up.
func _faces_selected() -> PackedByteArray:
	var em = ed.em
	var ts := PackedByteArray()
	ts.resize(em.tri_count())
	var sp: PackedByteArray = ed.sel_p
	for t in em.tri_count():
		if sp[em.tris[t * 3]] and sp[em.tris[t * 3 + 1]] and sp[em.tris[t * 3 + 2]]:
			ts[t] = 1
	if ed.sel_kind == 2:
		ts = ed.sel_t.duplicate()
	em.close_to_polys(ts)
	return ts


## Duplicate (Shift+D): the selected faces copied, the copy selected and moved (G). The copy is
## one undo step, the move another (cancelled, the copy stays where it was made).
func duplicate_selection() -> void:
	var em = ed.em
	if em == null or ed.mode != "edit":
		return
	cancel_loopcut()
	var ts := _faces_selected()
	if not ts.has(1):
		ed._say("Duplicate: select whole faces (points and edges alone copy nothing - the mesh is made of faces).")
		return
	var before: Dictionary = ed._snap()
	var top := duplicate_faces(em, ts)
	_select_points(top)
	ed._edit_done("Duplicate", before)
	ed._say("Duplicated %d faces (%d points) - move them, click to keep." % [_count_faces(em, ed.sel_t), top.size()])
	ed.begin_transform("G")


static func _count_faces(em, ts: PackedByteArray) -> int:
	var f := {}
	for t in mini(ts.size(), em.tri_count()):
		if ts[t]:
			f[em.tri_face[t]] = true
	return f.size()


## Merge by distance (Alt+M): the selected points (none: all) closer than `merge_dist` made one.
## One undo step; returns how many points went.
func merge_by_distance(dist := -1.0) -> int:
	var em = ed.em
	if em == null:
		return 0
	if dist < 0.0:
		dist = merge_dist
	var ids: PackedInt32Array = ed.selected_points()
	var close := close_points(em.points, ids, ids, dist)
	var n: int = close["removed"]
	if n == 0:
		ed._say("Merge by distance: no points closer than %s m%s." % [_fmt(dist), " among the selected" if not ids.is_empty() else ""])
		return 0
	var before: Dictionary = ed._snap()
	var old: PackedByteArray = ed.sel_p.duplicate()
	var map := weld(em, close)
	_remap_selection(map, old)
	ed._edit_done("Merge by distance", before)
	ed._say("Merge by distance: %d point%s removed (closer than %s m)." % [n, "" if n == 1 else "s", _fmt(dist)])
	return n


## Auto merge, as a transform `x` ends (mesh_editor.confirm_transform, before its undo step):
## the points it moved welded to any point within `merge_dist`. How many went.
func after_transform(x: Dictionary) -> int:
	if not auto_merge or ed.em == null:
		return 0
	var em = ed.em
	var moved: PackedInt32Array = x.get("all", x.get("ids", PackedInt32Array()))
	if moved.is_empty():
		return 0
	var fixed := PackedByteArray()
	fixed.resize(em.points.size())
	fixed.fill(1)
	for p in moved:
		fixed[p] = 0
	var close := close_points(em.points, moved, PackedInt32Array(range(em.points.size())), merge_dist, fixed)
	var n: int = close["removed"]
	if n == 0:
		return 0
	var old: PackedByteArray = ed.sel_p.duplicate()
	var map := weld(em, close)
	_remap_selection(map, old)
	ed._say("Auto merge: %d point%s welded." % [n, "" if n == 1 else "s"])
	return n


## The size of a screen pixel at `at` (global), in the part's own units.
func _px_local(at: Vector3) -> float:
	var view = ed.view
	var px := 0.0
	if view.cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		px = view.cam.size / maxf(view.size.y, 1.0)
	else:
		px = 2.0 * view.cam.global_position.distance_to(at) * tan(deg_to_rad(view.cam.fov * 0.5)) / maxf(view.size.y, 1.0)
	var sc: Vector3 = ed.part.global_transform.basis.get_scale()
	return px / maxf((sc.x + sc.y + sc.z) / 3.0, 0.0001)


# --- inset (I) ----------------------------------------------------------------------

## Inset (I): the selected faces inset as a region - the ring made at once, its width then set by
## the mouse (towards the selection's middle: wider) or typed (digits and a point; Backspace).
## Click / Enter keeps it (one undo step with the new faces), right-click / Esc cancels it all.
func begin_inset() -> void:
	var em = ed.em
	if em == null or ed.mode != "edit":
		return
	cancel_loopcut()
	ed._cancel_xf()
	var ts := _faces_selected()
	if not ts.has(1):
		ed._say("Inset: select faces first (3: face mode).")
		return
	var before: Dictionary = ed._snap()
	var r := inset_region(em, ts)
	if r.is_empty():
		em.restore(before)
		ed._say("Inset: the selected faces have no border to inset from (a closed region).")
		return
	_select_points(r["inner"])
	var all := PackedInt32Array(r["ids"])
	all.append_array(r["ring"])
	var x := {"kind": "INS", "name": "Inset", "snap": before, "m0": ed._mouse, "axis": -1, "dir": Vector3.ZERO,
		"pivot": ed.part.global_transform * em.centroid(r["inner"]), "ids": r["ids"], "orig": r["orig"], "dirs": r["dirs"],
		"all": PackedInt32Array(r["ids"]), "verts": em.verts_of(_all_of(r)), "typed": "", "step": _inset_step, "on_cancel": _undo_cancel}
	ed.xf = x
	ed._mesh_changed()
	ed._xf_update()


static func _all_of(r: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array(r["inner"])
	out.append_array(r["ring"])
	return out


## The inset's width now: typed, else by the mouse.
func inset_amount() -> float:
	var x: Dictionary = ed.xf
	if str(x.get("typed", "")) != "":
		return maxf(0.0, str(x["typed"]).to_float())
	if x.has("amount"):
		return float(x["amount"])
	var pivot: Vector3 = x["pivot"]
	var ps: Vector2 = ed.view.project(pivot)
	var m0: Vector2 = x["m0"]
	var d0 := (m0 - ps).length()
	var mouse: Vector2 = ed._mouse
	var d1 := (mouse - ps).length()
	var px := (d0 - d1) if d0 > 40.0 else (mouse - m0).length()   # (begun near the middle: as far as it's moved)
	return maxf(0.0, px) * _px_local(pivot)


func _inset_step() -> void:
	var em = ed.em
	var x: Dictionary = ed.xf
	var a := inset_amount()
	var ids: PackedInt32Array = x["ids"]
	var orig: PackedVector3Array = x["orig"]
	var dirs: PackedVector3Array = x["dirs"]
	var pts: PackedVector3Array = em.points
	for k in ids.size():
		pts[ids[k]] = orig[k] + dirs[k] * a
	em.points = pts
	em.sync(x["verts"])
	ed._refill = true
	ed._sync_sel_coords()
	var typed := str(x.get("typed", ""))
	ed.view.hint = "Inset  %s m%s   (mouse towards the middle: wider · type a width · click / Enter: done · right-click / Esc: cancel)" % [_fmt(a), "  [" + typed + "]" if typed != "" else ""]
	ed.view.request()


## A transform that changed the topology cancelled: the mesh and the selection as before it.
func _undo_cancel(x: Dictionary) -> void:
	var snap: Dictionary = x["snap"]
	ed.em.restore(snap)
	ed.sel_p = (snap["sel_p"] as PackedByteArray).duplicate()
	ed.sel_e = (snap["sel_e"] as PackedByteArray).duplicate()
	ed.sel_t = (snap["sel_t"] as PackedByteArray).duplicate()
	ed.sel_pa = (snap["sel_pa"] as PackedByteArray).duplicate()
	ed._resize_sel()
	ed._refill = false
	ed._mesh_changed()


## Keys while a tool of these runs (mesh_editor's key handling asks first): true if taken.
func key(k: InputEventKey) -> bool:
	if cutting and k.keycode == KEY_ESCAPE:
		cancel_loopcut()
		ed._say("Loop cut stopped.")
		return true
	var x: Dictionary = ed.xf
	if x.get("kind", "") != "INS" or k.ctrl_pressed:
		return false
	var typed := str(x.get("typed", ""))
	var kc := k.keycode
	if kc >= KEY_0 and kc <= KEY_9:
		typed += str(kc - KEY_0)
	elif kc >= KEY_KP_0 and kc <= KEY_KP_9:
		typed += str(kc - KEY_KP_0)
	elif (kc == KEY_PERIOD or kc == KEY_KP_PERIOD or kc == KEY_COMMA) and not typed.contains("."):
		typed += "."
	elif kc == KEY_BACKSPACE:
		typed = typed.substr(0, maxi(0, typed.length() - 1))
	else:
		return false
	x["typed"] = typed
	ed._xf_update()
	return true


# --- loop cut (Ctrl+R) ----------------------------------------------------------------

## Loop cut (Ctrl+R): from now the ring across the edge under the mouse is shown; a click cuts.
func begin_loopcut() -> void:
	if ed.em == null or ed.mode != "edit":
		return
	ed._cancel_xf()
	ed.knife_cancel()
	cutting = true
	_ring = {}
	ed._say("Loop cut: point at an edge - the ring of quads across it shows; click to cut (right-click / Esc: stop).")
	loopcut_hover(ed._mouse)


func cancel_loopcut() -> void:
	if not cutting:
		return
	cutting = false
	_ring = {}
	_show_ring({})


## The shown edge nearest `at` on the face under it: [a, b] (its points) or [].
func _edge_at(at: Vector2) -> Array:
	var em = ed.em
	var t: int = ed._pick_tri(at)
	if t < 0:
		return []
	var loop: PackedInt32Array = em.poly_loop(t)
	if loop.is_empty():
		loop = em.tris.slice(t * 3, t * 3 + 3)
	var best := []
	var bd := INF
	for k in loop.size():
		var a: int = loop[k]
		var b: int = loop[(k + 1) % loop.size()]
		var d := Geometry2D.get_closest_point_to_segment(at, ed._screen(a), ed._screen(b)).distance_to(at)
		if d < bd:
			bd = d
			best = [a, b]
	return best


## The rings a cut across edge a -> b makes: its own, and with symmetry on its mirror twins'.
func _rings(a: int, b: int) -> Array:
	var em = ed.em
	var out := [ring(em, a, b)]
	var taken := {}
	for s in out[0]["sides"]:
		taken[em.edge(s[0], s[1])] = true
	for ax in 3:
		if not ed.sym[ax]:
			continue
		var mm: PackedInt32Array = em.mirror_map(ax)
		var ta := mm[a] if a < mm.size() else -1
		var tb := mm[b] if b < mm.size() else -1
		if ta < 0 or tb < 0 or em.edge(ta, tb) < 0 or taken.has(em.edge(ta, tb)):
			continue
		var r2 := ring(em, ta, tb)
		if (r2["quads"] as PackedInt32Array).is_empty():
			continue
		for s in r2["sides"]:
			taken[em.edge(s[0], s[1])] = true
		out.append(r2)
	return out


func loopcut_hover(at: Vector2) -> void:
	if not cutting or ed.em == null:
		return
	var ab := _edge_at(at)
	if ab.is_empty():
		_ring = {}
		_show_ring({})
		return
	var key := "%d-%d" % [mini(ab[0], ab[1]), maxi(ab[0], ab[1])]
	if _ring.get("key", "") == key:
		return
	var rs := _rings(ab[0], ab[1])
	_ring = {"key": key, "a": ab[0], "b": ab[1], "rings": rs}
	_show_ring(_ring)


## The ring's new loop drawn (the knife's line, diamonds where it crosses the edges).
func _show_ring(r: Dictionary) -> void:
	var view = ed.view
	var pts := PackedVector3Array()
	var kinds := PackedInt32Array()
	if not r.is_empty() and (r["rings"][0]["quads"] as PackedInt32Array).size() > 0:
		var g: Transform3D = ed.part.global_transform
		var rr: Dictionary = r["rings"][0]
		for s in rr["sides"]:
			pts.append(g * (ed.em.points[s[0]] as Vector3).lerp(ed.em.points[s[1]], 0.5))
			kinds.append(1)
		if rr["closed"] and not pts.is_empty():
			pts.append(pts[0])
			kinds.append(1)
	view.knife_on = not pts.is_empty()
	view.knife_pts = pts
	view.knife_kinds = kinds
	view.knife_next = Vector3.INF
	view.knife_mouse = Vector2(-1, -1)
	view.knife_through = false
	view.queue_redraw()


## The cut made through the ring under `at` (or the one shown), then slid by the mouse.
## True if it cut.
func loopcut_click(at: Vector2) -> bool:
	loopcut_hover(at)
	if _ring.is_empty() or (_ring["rings"][0]["quads"] as PackedInt32Array).is_empty():
		ed._say("Loop cut: point at an edge with quads beside it.")
		return false
	return cut_loop(_ring["a"], _ring["b"])


## A new edge loop across edge a -> b (and its mirror twins with symmetry on), then the slide
## begins (xf "SLIDE"). True if it cut.
func cut_loop(a: int, b: int, slide := true) -> bool:
	var em = ed.em
	var rs := _rings(a, b)
	var chains := []
	var sides := []
	for r in rs:
		if (r["quads"] as PackedInt32Array).is_empty():
			continue
		chains.append(ring_chain(em, r, 0.5))
		for s in r["sides"]:
			sides.append([em.points[s[0]], em.points[s[1]]])
	if chains.is_empty():
		ed._say("Loop cut: no quads across that edge.")
		return false
	var a0: Vector3 = em.points[a]
	var b0: Vector3 = em.points[b]
	var before: Dictionary = ed._snap()
	var res: Dictionary = em.knife_apply(chains)
	cancel_loopcut()
	if not res["ok"]:
		em.restore(before)
		ed._say("Loop cut: %s - nothing cut." % res["why"])
		return false
	# each new point: the side it's on (by where it is - halfway along it)
	var news: PackedInt32Array = res["points"]
	var ids := PackedInt32Array()
	var ends_a := PackedVector3Array()
	var ends_b := PackedVector3Array()
	var grid := {}
	for p in news:
		grid[_cell(em.points[p])] = p
	for s in sides:
		var mid: Vector3 = (s[0] as Vector3).lerp(s[1], 0.5)
		var p := _near(em, grid, mid, news)
		if p >= 0 and not ids.has(p):
			ids.append(p)
			ends_a.append(s[0])
			ends_b.append(s[1])
	ed._resize_sel()
	ed.sel_p.fill(0)
	ed.sel_e.fill(0)
	ed.sel_t.fill(0)
	ed.sel_pa.fill(0)
	var se: PackedByteArray = ed.sel_e
	var cut: PackedInt32Array = res["cut"]
	for i in range(0, cut.size(), 2):
		var e: int = em.edge(cut[i], cut[i + 1])
		if e >= 0:
			se[e] = 1
	ed.sel_e = se
	var keep: int = ed.sel_kind
	ed.sel_kind = 1
	ed._derive_sel()
	ed.sel_kind = keep if keep != 2 else 1
	var x := {"kind": "SLIDE", "name": "Loop cut", "snap": before, "m0": ed._mouse, "axis": -1, "dir": Vector3.ZERO,
		"pivot": ed.part.global_transform * em.centroid(ids), "ids": ids, "a": ends_a, "b": ends_b, "all": ids,
		"verts": em.verts_of(ids), "f": 0.5, "sa": a0, "sb": b0, "step": _slide_step, "on_cancel": _slide_cancel}
	ed._mesh_changed()
	if not slide:
		ed._edit_done("Loop cut", before)
		ed._update_ui()
		return true
	ed.xf = x
	ed._xf_update()
	ed._say("Loop cut: %d new points - slide it along with the mouse, click to keep (right-click / Esc: in the middle)." % ids.size())
	return true


static func _cell(p: Vector3) -> Vector3i:
	return Vector3i((p * 1e5).round())


static func _near(em, grid: Dictionary, at: Vector3, news: PackedInt32Array) -> int:
	var c := _cell(at)
	if grid.has(c):
		return grid[c]
	var best := -1
	var bd := INF
	for p in news:
		var d: float = (em.points[p] as Vector3).distance_squared_to(at)
		if d < bd:
			bd = d
			best = p
	return best


## Where along the sides the new loop is (0: the a side, 1: the b side): by the mouse along the
## edge first pointed at, or `xf["fixed"]`.
func slide_amount() -> float:
	var x: Dictionary = ed.xf
	if x.has("fixed"):
		return float(x["fixed"])
	var g: Transform3D = ed.part.global_transform
	var sa: Vector2 = ed.view.project(g * (x["sa"] as Vector3))
	var sb: Vector2 = ed.view.project(g * (x["sb"] as Vector3))
	var d := sb - sa
	if d.length() < 4.0:
		return 0.5
	var m0: Vector2 = x["m0"]
	return clampf(0.5 + (ed._mouse - m0).dot(d) / d.length_squared(), 0.0, 1.0)


func _slide_step() -> void:
	var x: Dictionary = ed.xf
	var f := slide_amount()
	_place_slide(x, f)
	ed._refill = true
	ed._sync_sel_coords()
	ed.view.hint = "Loop cut  %d%%   (mouse along the edge: slide · click / Enter: done · right-click / Esc: in the middle)" % roundi(f * 100.0)
	ed.view.request()


func _place_slide(x: Dictionary, f: float) -> void:
	var em = ed.em
	var ids: PackedInt32Array = x["ids"]
	var a: PackedVector3Array = x["a"]
	var b: PackedVector3Array = x["b"]
	var pts: PackedVector3Array = em.points
	for k in ids.size():
		pts[ids[k]] = a[k].lerp(b[k], clampf(f, 0.0, 1.0))
	em.points = pts
	em.sync(x["verts"])


## The slide cancelled: the loop kept, in the middle (one undo step).
func _slide_cancel(x: Dictionary) -> void:
	_place_slide(x, 0.5)
	ed.em.recalc_normals(x["verts"])
	ed._refill = false
	ed._edit_done("Loop cut", x["snap"])
	ed._update_ui()


## The view's mouse (mesh_editor._view_input asks first): the loop cut's hover and click, Alt+click's
## loop. True if taken.
func view_input(e: InputEvent) -> bool:
	if ed.em == null or ed.mode != "edit":
		return false
	var mm := e as InputEventMouseMotion
	if mm:
		if cutting and ed._drag == "":
			loopcut_hover(mm.position)
		return false
	var mb := e as InputEventMouseButton
	if mb == null:
		return false
	if cutting:
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.alt_pressed:
			if mb.pressed:
				ed._mouse = mb.position
				loopcut_click(mb.position)
			return true
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				cancel_loopcut()
				ed._say("Loop cut stopped.")
			return true
		return false
	if mb.button_index == MOUSE_BUTTON_LEFT and ed.xf.is_empty() and ed.knife.is_empty():
		if mb.pressed and mb.alt_pressed:
			_alt_at = mb.position
		elif not mb.pressed and _alt_at.x >= 0.0:
			var near := mb.position.distance_to(_alt_at) <= 5.0
			_alt_at = Vector2(-1, -1)
			if near:
				select_loop_at(mb.position, mb.shift_pressed)
	return false


# --- select loop / ring -----------------------------------------------------------------

## Alt+click at `at`: the loop through the edge nearest the mouse (edge mode, Auto: the edges;
## vertex mode: their points) - in face mode the ring of quads across it. `add`: kept with what's
## selected.
func select_loop_at(at: Vector2, add := false) -> bool:
	var em = ed.em
	var ab := _edge_at(at)
	if ab.is_empty():
		return false
	var e: int = em.edge(ab[0], ab[1])
	if e < 0:
		return false
	if ed.sel_kind == 2:
		_select_ring_faces(ab[0], ab[1], add)
	else:
		_select_edges(edge_loop(em, e), add)
	return true


## The edges `es` selected (vertex mode: their points), with their mirror twins.
func _select_edges(es: PackedInt32Array, add: bool) -> void:
	var em = ed.em
	if not add:
		ed.sel_p.fill(0)
		ed.sel_e.fill(0)
		ed.sel_t.fill(0)
		ed.sel_pa.fill(0)
	if ed.sel_kind == 0:
		var sp: PackedByteArray = ed.sel_p
		for e in es:
			sp[em.edges[e * 2]] = 1
			sp[em.edges[e * 2 + 1]] = 1
		ed.sel_p = sp
		for e in es:
			ed._twins(0, em.edges[e * 2], 1)
			ed._twins(0, em.edges[e * 2 + 1], 1)
	else:
		var se: PackedByteArray = ed.sel_e
		for e in es:
			se[e] = 1
		ed.sel_e = se
		for e in es:
			ed._twins(1, e, 1)
	ed._derive_sel()
	ed._overlays()


func _select_ring_faces(a: int, b: int, add: bool) -> void:
	var em = ed.em
	if not add:
		ed.sel_p.fill(0)
		ed.sel_e.fill(0)
		ed.sel_t.fill(0)
		ed.sel_pa.fill(0)
	var r := ring(em, a, b)
	for t in r["quads"]:
		ed._set_poly(t, 1)
	ed._derive_sel()
	ed._overlays()


## The selected edges (any mode) as [edges].
func _sel_edges() -> PackedInt32Array:
	var out := PackedInt32Array()
	var se: PackedByteArray = ed.sel_e
	for e in mini(se.size(), ed.em.edge_count()):
		if se[e] and _shown(ed.em, e):
			out.append(e)
	return out


## Select loop: each selected edge's loop added. How many edges are selected afterwards.
func select_loops() -> int:
	return _extend(edge_loop)


## Select ring: each selected edge's ring added.
func select_rings() -> int:
	return _extend(edge_ring)


func _extend(of: Callable) -> int:
	var em = ed.em
	if em == null:
		return 0
	var es := _sel_edges()
	if es.is_empty():
		ed._say("Select an edge first (2: edge mode), or Alt+click one.")
		return 0
	var all := {}
	for e in es:
		for e2 in of.call(em, e):
			all[e2] = true
	var keep: int = ed.sel_kind
	if keep == 2:
		ed.sel_kind = 1   # (a face's edges extended: shown as edges)
	_select_edges(PackedInt32Array(all.keys()), true)
	ed._update_ui()
	return all.size()
