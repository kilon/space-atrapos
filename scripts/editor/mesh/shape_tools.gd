extends Node
## The mesh editor's shapes and booleans (a node of the editor, `ed`): the shape
## library and its browser (the Shapes tab), the SHAPE panel (a shape's parameters;
## a part made from a shape made again as they change), adding shapes (double-click,
## drag into the view), saving new ones; and the BOOLEAN panel - union, difference,
## intersection, slice of two parts (mesh_bool.gd, on a worker), undoable.
## A part made from a shape keeps its recipe in its "mesh_shape" meta
## ({id, name, gen, params}) - until its vertices are edited (then it's a plain mesh);
## saved in the glb's extras ("atrapos_shape"), read back when it's opened.

const Shapes := preload("res://scripts/editor/mesh/shapes.gd")
const ShapeLibrary := preload("res://scripts/editor/mesh/shape_library.gd")
const ShapeBrowser := preload("res://scripts/editor/mesh/shape_browser.gd")
const ShapePanel := preload("res://scripts/editor/mesh/shape_panel.gd")
const MeshBool := preload("res://scripts/editor/mesh/mesh_bool.gd")
const MeshIO := preload("res://scripts/editor/mesh/mesh_io.gd")
const MeshThumbs := preload("res://scripts/editor/mesh/mesh_thumbs.gd")

var ed: Control
var lib: ShapeLibrary
var browser: ShapeBrowser
var panel: ShapePanel
## The library shape picked in the browser ("": none).
var picked := ""
## Booleans keep B (hidden) instead of removing it.
var keep_b := false
## A boolean is being worked out (on a worker).
var busy := false
var _bool_btns := {}
var _bool_note: Label
var _keep_box: CheckBox
var _task := -1
var _task_out: Array = []
var _task_ctx := {}
var _gen_task := -1
var _gen_out: Array = []
var _gen_cur := {}
var _gen_queue: Array = []        # requests: {kind: "preview" / "part" / "add", entry, ...}
var _shape_before := {}           # a part's shape being changed: {part, mesh, meta} before


func setup(editor: Control) -> void:
	ed = editor
	name = "ShapeTools"
	var thumbs: Node = MeshThumbs.new()   # (its own: shapes drawn while the models list draws its own)
	thumbs.name = "ShapeThumbs"
	add_child(thumbs)
	lib = ShapeLibrary.new()
	lib.load_all()
	browser = ShapeBrowser.new()
	browser.name = "ShapeBrowser"
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.setup(lib, thumbs)
	browser.picked.connect(pick)
	browser.activated.connect(func(id): add_shape(id))
	panel = ShapePanel.new()
	panel.name = "ShapePanel"
	panel.param_changed.connect(_param_changed)
	panel.add_requested.connect(func():
		if picked != "":
			add_shape(picked))
	panel.save_requested.connect(save_dialog)
	panel.rename_requested.connect(rename_dialog)
	panel.delete_requested.connect(delete_picked)


func _exit_tree() -> void:
	for t in [_task, _gen_task]:
		if t >= 0:
			WorkerThreadPool.wait_for_task_completion(t)
	if _task_ctx.has("prep"):
		for r in MeshBool.take(_task_ctx["prep"]):
			r.free()
	_task = -1
	_gen_task = -1


## The BOOLEAN and SHAPE sections of the right panel, into `box`.
func build_right(box: VBoxContainer) -> void:
	box.add_child(EditorIcons.tipped(UI.section("BOOLEAN"), EditorIcons.tip("Boolean", "", "Two parts made one, cut or trimmed - as solids: join, subtract, intersect, slice.")))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 2)
	row.add_theme_constant_override("v_separation", 2)
	for o in bool_items():
		var b := UI.button("", func(): pass, 14)
		b.focus_mode = Control.FOCUS_NONE
		EditorIcons.dress(b, o[0], EditorIcons.tip(o[1], o[2], o[3]), {"union": "Union", "difference": "Subtract", "intersection": "Intersect", "slice": "Slice"}[o[5]])
		b.text = ""   # (an icon: its tooltip names it)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(32, 30)
		b.name = "Bool_" + str(o[5])
		var cb: Callable = o[4]
		b.pressed.connect(func(): cb.call())
		_bool_btns[o[5]] = b
		row.add_child(b)
	_keep_box = CheckBox.new()
	_keep_box.text = "Keep B"
	_keep_box.focus_mode = Control.FOCUS_NONE
	_keep_box.add_theme_font_size_override("font_size", 14)
	_keep_box.tooltip_text = EditorIcons.tip("Keep the cutter", "", "After a boolean, part B is hidden instead of removed (the eye in the parts list shows it again).")
	_keep_box.toggled.connect(func(on): keep_b = on)
	row.add_child(_keep_box)   # (beside the tools: one row)
	box.add_child(row)
	_bool_note = UI.note("", 14, 200)   # (kept for its messages, not shown: the tools' tooltips say what they need)
	_bool_note.visible = false
	box.add_child(_bool_note)
	box.add_child(EditorIcons.tipped(UI.section("SHAPE"), EditorIcons.tip("Shape", "", "The selected shape from the library: its settings, made again as you change them.")))
	box.add_child(panel)
	refresh()


## [icon, name, keys, help, Callable, op, enabled] for the boolean tools (the panel and the right-click menu).
func bool_items() -> Array:
	var pr := bool_pair()
	var ok := not pr.is_empty() and not busy
	var an: String = str(pr[0].name) if not pr.is_empty() else "A"
	var bn: String = str(pr[1].name) if not pr.is_empty() else "B"
	var how := "Select two parts (Ctrl / Shift+click, in the view or the parts list): A is the one selected first, B the other -\nor right-click a part with another selected (A: the selected one, B: the one under the mouse)."
	return [
		["m_union", "Union", "", "%s and %s made one solid part (it replaces %s; %s goes).\n%s" % [an, bn, an, bn, how], func(): boolean("union"), "union", ok],
		["m_difference", "Difference (A minus B)", "", "%s with %s cut out of it.\n%s" % [an, bn, how], func(): boolean("difference"), "difference", ok],
		["m_intersect", "Intersection", "", "Only what %s and %s share.\n%s" % [an, bn, how], func(): boolean("intersection"), "intersection", ok],
		["m_slice", "Slice", "", "%s cut in two by %s: the piece inside %s becomes a part of its own, the rest stays %s.\n%s" % [an, bn, bn, an, how], func(): boolean("slice"), "slice", ok],
	]


## The two parts a boolean works on: [A, B] - two selected (A first), or the selected one and
## the part right-clicked; [] if there aren't two.
func bool_pair() -> Array:
	var sel: Array = ed.selected_parts()
	if sel.size() >= 2:
		return [sel[sel.size() - 2], sel[sel.size() - 1]]
	var prev = ed.get("_menu_prev")
	if prev is MeshInstance3D and is_instance_valid(prev) and prev.is_inside_tree() and ed.part and prev != ed.part:
		return [prev, ed.part]
	return []


## The panels follow the selection.
func refresh() -> void:
	var pr := bool_pair()
	for o in bool_items():
		if _bool_btns.has(o[5]):
			var b: Button = _bool_btns[o[5]]
			b.disabled = not o[6]
			b.tooltip_text = EditorIcons.tip(o[1], o[2], o[3])
	if _bool_note:
		_bool_note.text = ("Working it out..." if busy else ("A: %s   B: %s" % [pr[0].name, pr[1].name] if not pr.is_empty() else "Select two parts."))
	_show_panel()


func _show_panel() -> void:
	if panel == null or not panel.is_inside_tree():
		return
	var p: MeshInstance3D = ed.part
	if p and p.has_meta("mesh_shape"):
		var m: Dictionary = p.get_meta("mesh_shape")
		if panel.mode != "part" or (panel.get_meta("part") if panel.has_meta("part") else null) != p:
			panel.set_meta("part", p)
			panel.show_shape("part", "Part %s - %s" % [p.name, m.get("name", m.get("gen", ""))], str(m.get("gen", "")), m.get("params", {}))
		return
	panel.set_meta("part", null)
	if picked != "" and lib.shapes.has(picked):
		var e := lib.entry(picked)
		if panel.mode != "library" or panel.get_meta("picked", "") != picked:
			panel.set_meta("picked", picked)
			panel.show_shape("library", "%s  (%s)" % [e.get("name", picked), e.get("cat", "")], str(e.get("gen", "")), e.get("params", {}))
			_gen({"kind": "preview", "entry": e.duplicate(true)})
		return
	panel.set_meta("picked", "")
	if p:
		panel.show_shape("mesh", "Part %s - a mesh of its own (Save keeps it as a shape)" % p.name, "mesh", {})
	else:
		panel.show_shape("", "", "", {})


## A shape of the library picked (its parameters in the SHAPE panel).
func pick(id: String) -> void:
	picked = id
	panel.set_meta("picked", "")
	if ed.part and ed.part.has_meta("mesh_shape"):
		ed.select_part(null)   # (the panel is the picked shape's now)
	_show_panel()


# --- making shapes (workers) -------------------------------------------------------------

func _gen(req: Dictionary) -> void:
	if req["kind"] != "add":   # (a newer preview / part request replaces an older one)
		for k in range(_gen_queue.size() - 1, -1, -1):
			if _gen_queue[k]["kind"] == req["kind"]:
				_gen_queue.remove_at(k)
	_gen_queue.append(req)


func _process(_dt: float) -> void:
	if _gen_task >= 0 and WorkerThreadPool.is_task_completed(_gen_task):
		WorkerThreadPool.wait_for_task_completion(_gen_task)
		_gen_task = -1
		var m: Mesh = _gen_out[0] if not _gen_out.is_empty() else null
		_gen_out = []
		_gen_done(_gen_cur, m)
		_gen_cur = {}
	if _gen_task < 0 and not _gen_queue.is_empty():
		_gen_cur = _gen_queue.pop_front()
		var e: Dictionary = _gen_cur["entry"]
		_gen_out = []
		_gen_task = WorkerThreadPool.add_task(func(): _gen_out = [ShapeLibrary.mesh_of(e)], false, "mesh editor: a shape")
	if _task < 0 and _task_ctx.has("prep") and Engine.get_process_frames() > int(_task_ctx["frame"]):
		var c := _task_ctx
		var roots := MeshBool.take(c["prep"])
		c.erase("prep")
		_task = WorkerThreadPool.add_task(func(): _task_out = [MeshBool.run(c["am"], c["bm"], c["b_in_a"], c["op"], roots)], false, "mesh editor: boolean")
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		busy = false
		var r: Dictionary = _task_out[0] if not _task_out.is_empty() else {"meshes": [], "error": "it failed"}
		_task_out = []
		_bool_apply(_task_ctx, r)
		_task_ctx = {}
		refresh()


func _gen_done(req: Dictionary, m: Mesh) -> void:
	match req.get("kind", ""):
		"preview":
			if panel.mode == "library":
				panel.set_preview(m)
		"part":
			var p: MeshInstance3D = req["part"]
			if m == null or not is_instance_valid(p) or not p.has_meta("mesh_shape"):
				return
			if JSON.stringify(p.get_meta("mesh_shape").get("params", {}), "", true) != JSON.stringify(req["entry"].get("params", {}), "", true):
				return   # (changed again since - or undone)
			_put_mesh(p, m)
		"add":
			if m == null:
				ed._say("Couldn't make the shape %s." % req["entry"].get("name", ""))
				return
			_add_mesh(req["id"], req["entry"], m, req.get("at", Vector3.INF))


## `p` gets mesh `m` (the old mesh's first material kept).
func _put_mesh(p: MeshInstance3D, m: Mesh) -> void:
	var mat: Material = p.mesh.surface_get_material(0) if p.mesh and p.mesh.get_surface_count() > 0 else null
	if mat and m.get_surface_count() > 0:
		m.surface_set_material(0, mat)
	p.mesh = m
	ed._place_ghosts()
	ed.view.request()


# --- adding shapes ----------------------------------------------------------------------

## Adds library shape `id` as a new part (made on a worker; `at`: where - its bottom there -
## else the model's origin).
func add_shape(id: String, at := Vector3.INF) -> void:
	var e := lib.entry(id)
	if e.is_empty():
		return
	ed._say("Adding %s..." % e.get("name", id))
	_gen({"kind": "add", "id": id, "entry": e.duplicate(true), "at": at})


## The same, made now (tests, scripts): the new part.
func add_shape_now(id: String, at := Vector3.INF) -> MeshInstance3D:
	var e := lib.entry(id)
	if e.is_empty():
		return null
	var m := ShapeLibrary.mesh_of(e)
	return _add_mesh(id, e, m, at) if m else null


func _add_mesh(id: String, e: Dictionary, m: Mesh, at: Vector3) -> MeshInstance3D:
	if ed.mode == "edit":
		ed._leave_edit(true)
	if ed.model == null:
		ed.new_model(true)
	var mi := MeshInstance3D.new()
	if m.get_surface_count() > 0 and m.surface_get_material(0) == null:
		m.surface_set_material(0, MeshIO.default_material())
	mi.mesh = m
	mi.name = ed._unique(str(e.get("name", id)).to_pascal_case().validate_node_name())
	if str(e.get("gen", "")) != "mesh":
		mi.set_meta("mesh_shape", {"id": id, "name": e.get("name", id), "gen": e["gen"], "params": Shapes.full_params(e["gen"], e.get("params", {}))})
	if at != Vector3.INF:
		var inv: Transform3D = ed.model.global_transform.affine_inverse()
		mi.position = inv * at - Vector3(0, m.get_aabb().position.y, 0)
	var model: Node3D = ed.model
	var add := func():
		model.add_child(mi)
		mi.owner = model
		ed._bind_new(mi)
		ed._fill_parts()
		ed.select_part(mi)
	var remove := func():
		model.remove_child(mi)
		if ed.part == mi:
			ed.part = null
		ed._fill_parts()
		ed._show_part()
		ed._update_ui()
		ed.view.request()
	ed._do("Add " + str(e.get("name", id)), add, remove, [mi])
	ed._say("Added %s (%s): its parameters are in the SHAPE panel." % [mi.name, e.get("name", id)])
	return mi


## Where a shape dropped at `at` (the view's point) goes: the surface under the mouse, else
## the ground (y = 0), else in front of the camera.
func drop_point(at: Vector2) -> Vector3:
	return drop_hit(at)[0]


## Where a drop at `at` lands: [the point (the nearest solid under it, else the ground, else ahead of the
## camera), the surface's normal there].
func drop_hit(at: Vector2) -> Array:
	var r: Array = ed.view.ray(at)
	var o: Vector3 = r[0]
	var d: Vector3 = (r[1] as Vector3).normalized()
	var best := INF
	var hit := Vector3.INF
	var nrm := Vector3.UP
	for p: MeshInstance3D in ed.parts():
		if not p.is_visible_in_tree() or p.mesh == null:
			continue
		var tm := p.mesh.generate_triangle_mesh()   # (cached by the mesh)
		if tm == null:
			continue
		var inv := p.global_transform.affine_inverse()
		var h := tm.intersect_ray(inv * o, (inv.basis * d).normalized())
		if h.is_empty():
			continue
		var w: Vector3 = p.global_transform * (h["position"] as Vector3)
		if w.distance_to(o) < best:
			best = w.distance_to(o)
			hit = w
			nrm = (p.global_transform.basis.inverse().transposed() * (h["normal"] as Vector3)).normalized()
	if hit != Vector3.INF:
		if nrm.dot(d) > 0.0:
			nrm = -nrm   # (the side facing the camera)
		return [hit, nrm]
	var g = Plane(Vector3.UP, 0.0).intersects_ray(o, d)
	if g != null:
		return [g, Vector3.UP]
	return [o + d * 3.0, -d]


# --- the selected part's shape -----------------------------------------------------------

func _param_changed(key: String, v: float, final: bool) -> void:
	if panel.mode == "library":
		var e := lib.entry(picked).duplicate(true)
		e["params"] = panel.params.duplicate()
		_gen({"kind": "preview", "entry": e})
		return
	if panel.mode != "part":
		return
	set_part_param(ed.part, key, v, final)


## Changes parameter `key` of part `p`'s shape: the part made again (on a worker; `now`: here);
## `final`: one undo step for the change (a slider let go, a value typed).
func set_part_param(p: MeshInstance3D, key: String, v: float, final := true, now := false) -> void:
	if p == null or not p.has_meta("mesh_shape"):
		return
	var meta: Dictionary = p.get_meta("mesh_shape").duplicate(true)
	if _shape_before.is_empty() or _shape_before["part"] != p:
		_shape_before = {"part": p, "mesh": p.mesh, "meta": meta.duplicate(true)}
	meta["params"][key] = v
	p.set_meta("mesh_shape", meta)
	var e := {"gen": meta["gen"], "params": meta["params"], "name": meta.get("name", "")}
	if now or final:
		var m := Shapes.make(str(meta["gen"]), meta["params"])
		if m:
			_put_mesh(p, m)
	else:
		_gen({"kind": "part", "part": p, "entry": e})
	if final:
		var b: Dictionary = _shape_before
		_shape_before = {}
		var after_mesh: Mesh = p.mesh
		var after_meta := meta.duplicate(true)
		var put := func(m: Mesh, mt: Dictionary):
			p.mesh = m
			p.set_meta("mesh_shape", mt.duplicate(true))
			panel.set_meta("part", null)
			ed._place_ghosts()
			refresh()
			ed.view.request()
		ed._push("Shape " + key, put.bind(b["mesh"], b["meta"]), put.bind(after_mesh, after_meta))


# --- saving shapes ------------------------------------------------------------------------

## Saves a new shape (`from_part`: the selected part's recipe - or its mesh; else the picked
## shape with the panel's parameters) and writes the library. The new id ("" if it couldn't).
func save_new(name: String, cat: String, from_part := true) -> String:
	var id := ""
	var p: MeshInstance3D = ed.part
	if from_part and p:
		if p.has_meta("mesh_shape"):
			var m: Dictionary = p.get_meta("mesh_shape")
			id = lib.add(name, cat, m["gen"], m["params"])
		else:
			id = lib.add_mesh(name, cat, ed.mirrored_mesh(p))
	elif picked != "" and panel.gen != "" and panel.gen != "mesh":
		id = lib.add(name, cat, panel.gen, panel.params)
	elif picked != "":   # (a mesh shape: copied)
		var e := lib.entry(picked)
		var m := ShapeLibrary.mesh_of(e)
		id = lib.add_mesh(name, cat, m) if m else ""
	if id == "":
		ed._say("Couldn't keep the shape.")
		return ""
	var err := lib.save()
	browser.fill_cats()
	browser.select_id(id)
	picked = id
	ed._say(("Kept the shape %s in %s (%s)." % [name, lib.entry(id).get("cat", ""), EditTarget.label()]) if err == OK else "Couldn't save the shape library (%s)." % error_string(err))
	return id


func _dialog(title: String, text: String, name0: String, cat0: String, go: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.name = "ShapeDialog"
	ed.add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var box := UI.modal(root, Color(1.0, 0.72, 0.38), Vector2(560, 0))
	box.add_child(UI.label(title, 24, NeonTheme.HEAD))
	box.add_child(UI.note(text, 15, 500))
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	grid.add_child(UI.label("Name", 16, UI.TEXT_DIM))
	var le := LineEdit.new()
	le.text = name0
	le.custom_minimum_size.x = 360
	le.add_theme_font_size_override("font_size", 16)
	grid.add_child(le)
	grid.add_child(UI.label("Category", 16, UI.TEXT_DIM))
	var cat := OptionButton.new()
	cat.add_theme_font_size_override("font_size", 16)
	var cats: Array = lib.categories.duplicate()
	if not ShapeLibrary.USER_CAT in cats:
		cats.append(ShapeLibrary.USER_CAT)
	for c in cats:
		cat.add_item(str(c))
	cat.select(maxi(cats.find(cat0), 0))
	grid.add_child(cat)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var ok := func():
		var n := le.text.strip_edges()
		if n == "":
			return
		layer.queue_free()
		go.call(n, cat.get_item_text(cat.selected))
	le.text_submitted.connect(func(_t): ok.call())
	row.add_child(UI.button("Cancel", layer.queue_free, 16))
	row.add_child(UI.button("Keep", ok, 16))
	le.grab_focus.call_deferred()


## "Save as new shape": a name and a category asked, then save_new().
func save_dialog() -> void:
	if not EditTarget.writable():
		ed._say("Saving isn't possible here (an exported game): make a mod and edit it in the Mod Editor.")
		return
	var p: MeshInstance3D = ed.part
	var from_part := p != null and panel.mode != "library"
	var base: String = (str(p.get_meta("mesh_shape", {}).get("name", p.name)) if from_part else str(lib.entry(picked).get("name", "Shape")))
	var what := ("the part's recipe (%s and its parameters)" % p.get_meta("mesh_shape")["gen"] if p.has_meta("mesh_shape") else "the part's mesh itself") if from_part else "the picked shape with these parameters"
	_dialog("Save as new shape", "Keeps %s as a shape of the library - saved into %s." % [what, EditTarget.label()], base + " 2", ShapeLibrary.USER_CAT,
		func(n, c): save_new(n, c, from_part))


func rename_dialog() -> void:
	if picked == "":
		return
	var e := lib.entry(picked)
	var id := picked
	var go := func(n: String, c: String):
		lib.rename(id, n, c)
		var err := lib.save()
		browser.fill_cats()
		browser.select_id(id)
		panel.set_meta("picked", "")
		_show_panel()
		ed._say("Renamed." if err == OK else "Couldn't save the shape library (%s)." % error_string(err))
	if e.get("builtin", false):
		UI.confirm(ed, "Rename a built-in shape?", "%s is one of the shapes the game comes with. Rename it anyway?" % e.get("name", id),
			func(): _dialog("Rename shape", "Its name and category.", str(e.get("name", id)), str(e.get("cat", "")), go), "Rename", "Cancel")
	else:
		_dialog("Rename shape", "Its name and category.", str(e.get("name", id)), str(e.get("cat", "")), go)


## Removes the picked shape from the library (a built-in one: asked first).
func delete_picked(confirmed := false) -> void:
	if picked == "":
		return
	var e := lib.entry(picked)
	if e.get("builtin", false) and not confirmed:
		UI.confirm(ed, "Remove a built-in shape?", "%s is one of the 120 shapes the game comes with. Remove it from the library%s?" % [e.get("name", picked), " (in your mod only)" if EditTarget.is_mod() else ""],
			func(): delete_picked(true), "Remove", "Cancel")
		return
	var id := picked
	lib.remove(id)
	var err := lib.save()
	picked = ""
	browser.fill_cats()
	_show_panel()
	ed._say(("Removed the shape %s." % e.get("name", id)) if err == OK else "Couldn't save the shape library (%s)." % error_string(err))


# --- booleans -------------------------------------------------------------------------------

## Boolean `op` (union, difference, intersection, slice) of parts `a` and `b` (null: the
## pair selected) - worked out on a worker, then one undo step.
func boolean(op: String, a: MeshInstance3D = null, b: MeshInstance3D = null, now := false) -> bool:
	if a == null or b == null:
		var pr := bool_pair()
		if pr.is_empty():
			ed._say("A boolean needs two parts: select one, then Ctrl+click (or Shift+click) the other.")
			return false
		a = pr[0]
		b = pr[1]
	if busy:
		return false
	for q in [a, b]:
		if q.skin != null or (q.mesh and q.mesh.get_surface_count() > 0 and q.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_BONES):
			ed._say("%s is skinned to a skeleton: a boolean would lose its weights - unbind it first (Unbind, in the PART panel)." % q.name)
			return false
	if ed.mode == "edit":
		ed._leave_edit(true)
	var am: Mesh = ed.mirrored_mesh(a)
	var bm: Mesh = ed.mirrored_mesh(b)
	var b_in_a: Transform3D = a.global_transform.affine_inverse() * b.global_transform
	var ctx := {"op": op, "a": a, "b": b, "t0": Time.get_ticks_usec()}
	if now:
		_bool_apply(ctx, MeshBool.run(am, bm, b_in_a, op))
		return true
	busy = true
	_task_ctx = ctx
	_task_out = []
	ctx["am"] = am
	ctx["bm"] = bm
	ctx["b_in_a"] = b_in_a
	ctx["prep"] = MeshBool.prepare(2 if op == "slice" else 1)   # (the CSG roots: made ready over a frame)
	ctx["frame"] = Engine.get_process_frames()
	var tris := 0
	for m in [am, bm]:
		for s in m.get_surface_count():
			var n: int = m.surface_get_array_index_len(s)
			tris += (n if n > 0 else m.surface_get_array_len(s)) / 3
	ed._say("%s of %s and %s (%d triangles): working it out..." % [MeshBool.LABEL[op], a.name, b.name, tris])
	refresh()
	return true


func _bool_apply(ctx: Dictionary, r: Dictionary) -> void:
	var a: MeshInstance3D = ctx["a"]
	var b: MeshInstance3D = ctx["b"]
	var op: String = ctx["op"]
	var ms := (Time.get_ticks_usec() - int(ctx["t0"])) / 1000.0
	if str(r.get("error", "")) != "":
		ed._say("%s: can't - %s." % [MeshBool.LABEL[op], r["error"]])
		return
	if not is_instance_valid(a) or not is_instance_valid(b) or not a.is_inside_tree():
		return
	var meshes: Array = r["meshes"]
	var a_mesh: Mesh = a.mesh
	var a_mirror: Dictionary = a.get_meta("mesh_mirror", {})
	var a_shape: Dictionary = a.get_meta("mesh_shape", {})
	var a_curves: Dictionary = a.get_meta("curve_solid", {})
	# (both made from curves: the result stays live - a recipe "A op B" made again whenever either's
	# curves change; B where it is in A now)
	var live := {}
	if not a_curves.is_empty() and b.has_meta("curve_solid") and op != "slice":
		var CT: GDScript = load("res://scripts/editor/mesh/curve_tools.gd")
		live = {"kind": "bool", "op": op, "a": a_curves, "b": b.get_meta("curve_solid"),
			"b_xf": CT.xf_arr(a.global_transform.affine_inverse() * b.global_transform)}
	var live_key: String = ed.curve_tools._solid_key(live) if not live.is_empty() else ""
	var new_a: Mesh = meshes[meshes.size() - 1]
	var piece: MeshInstance3D = null
	if op == "slice":
		piece = MeshInstance3D.new()
		piece.mesh = meshes[0]
		piece.name = ed._unique(str(a.name) + "Slice")
		piece.transform = a.transform
	var a_parent := a.get_parent()
	var b_parent := b.get_parent()
	var b_at := b.get_index()
	var b_vis := b.visible
	var keep := keep_b
	var model: Node3D = ed.model
	var do_it := func():
		a.mesh = new_a
		a.remove_meta("mesh_mirror")
		a.remove_meta("mesh_shape")
		if live.is_empty():
			a.remove_meta("curve_solid")   # (a plain mesh after a boolean with a plain mesh)
		else:
			a.set_meta("curve_solid", live)
			a.set_meta("curve_solid_key", live_key)
		ed._make_ghosts(a)
		if piece:
			a_parent.add_child(piece)
			a_parent.move_child(piece, a.get_index() + 1)
			piece.owner = model
		if keep:
			b.visible = false
		else:
			ed._free_ghosts(b)
			b_parent.remove_child(b)
		ed._fill_parts()
		ed.select_part(a)
	var undo_it := func():
		a.mesh = a_mesh
		if not a_mirror.is_empty():
			a.set_meta("mesh_mirror", a_mirror)
		if not a_shape.is_empty():
			a.set_meta("mesh_shape", a_shape)
		if not a_curves.is_empty():
			a.set_meta("curve_solid", a_curves)
		ed._make_ghosts(a)
		if piece and piece.get_parent():
			piece.get_parent().remove_child(piece)
		if keep:
			b.visible = b_vis
		elif b.get_parent() == null:
			b_parent.add_child(b)
			b_parent.move_child(b, mini(b_at, b_parent.get_child_count() - 1))
			b.owner = model
			if b.has_meta("mesh_mirror"):
				ed._make_ghosts(b)
		ed._fill_parts()
		ed.select_part(a)
	ed._do(MeshBool.LABEL[op], do_it, undo_it, [piece, b] if piece else [b])
	var tris := 0
	for m in meshes:
		for s in m.get_surface_count():
			tris += m.surface_get_array_index_len(s) / 3
	ed._say("%s of %s and %s: done in %.0f ms (%d triangles)%s%s." % [MeshBool.LABEL[op], a.name, b.name, ms, tris,
		(", the inside piece is " + str(piece.name)) if piece else "", " - live: it follows both solids' curves" if not live.is_empty() else ""])
