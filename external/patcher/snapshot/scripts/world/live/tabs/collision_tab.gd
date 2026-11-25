extends VBoxContainer
## The Live Editor's Collision tab: what's solid in the place picked - a town's
## buildings, a structure of yours, a station's parts, a port's walls and things,
## a ship's furniture, a dungeon's walls - its boxes drawn in the world as lines
## (near the camera), picked with a click there or from the list, moved, sized,
## turned, added, copied, deleted, made solid or not. The walker and the camera
## meet the edited boxes at once (SolidsEdit sets them into the place's own lookups).
## Kept (LiveEdits, section "collision"): the edit as a difference from what the
## place builds (SolidsEdit.record) - put back each time it's built (its builder:
## SolidsEdit.installed), so it holds for that place (its key: town by its seed,
## station by its id...).

const TITLE := "Collision"
const ICON := "wall"
const REACH := 60.0          # m: the boxes drawn and listed round the camera
const LISTED := 200          # (the list's longest)
const C_SOLID := Color(0.35, 0.9, 1.0, 0.8)
const C_FEET := Color(0.45, 1.0, 0.5, 0.8)
const C_CAM := Color(0.75, 0.55, 1.0, 0.8)
const C_OFF := Color(0.6, 0.6, 0.6, 0.45)
const C_SEL := Color(1.0, 0.72, 0.2, 1.0)
const KINDS := {"box": "box", "obox": "box", "cyl": "cylinder", "prism": "sloped block"}
const USES := [["both", "Camera and feet"], ["cam", "Camera only"], ["walk", "Feet only"]]

var ed: Node
var _owner: Node             # what holds the solids (SolidsEdit.owner_of the picked)
var _anchor: Node
var _key := ""
var _rel := "."
var _rot := "none"
var _shapes: Array = []      # SolidsEdit shapes, as edited
var _sel := -1
var _listed: Array = []      # the list's rows -> shape index
var _info: Label
var _list: ItemList
var _fields: VBoxContainer
var _xray: CheckBox
var _overlay: MeshInstance3D
var _im: ImmediateMesh
var _drawn_at := Vector3.INF
var _redraw := true
var _t := 0.0

static var _mat_depth: StandardMaterial3D
static var _mat_xray: StandardMaterial3D


static func handles(n: Node) -> bool:
	return SolidsEdit.owner_of(n) != null


## A kept edit put back on `anchor` (LiveEdits - as such a place is made): on its
## solids' holder at `path` under it.
static func apply_edit(anchor: Node, data: Dictionary) -> void:
	var o: Node = LiveEdits.find(anchor, str(data.get("path", ".")))
	if o == null or SolidsEdit.kind_of(o) == "":
		o = SolidsEdit.owner_of(anchor)
	if o:
		SolidsEdit.apply_record(o, data)


func bind(e: Node) -> void:
	ed = e
	add_theme_constant_override("separation", 6)
	_owner = SolidsEdit.owner_of(ed.selected)
	var a := LiveEdits.anchor_of(_owner)
	_anchor = a[0]
	_key = a[1]
	_rel = LiveEdits.rel_path(_anchor, _owner) if _anchor else "."
	_rot = SolidsEdit.rotation_of(_owner)
	add_child(LiveFields.head("SOLIDS"))
	_info = UI.note("", 13, 420.0)
	add_child(_info)
	_xray = CheckBox.new()
	_xray.text = "Show through walls"
	_xray.focus_mode = Control.FOCUS_NONE
	_xray.add_theme_font_size_override("font_size", 13)
	_xray.tooltip_text = EditorIcons.tip("Show through walls", "", "Draws the solid boxes over everything, not hidden behind walls and floors.")
	_xray.toggled.connect(func(_v): _redraw = true)
	add_child(_xray)
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 220)
	_list.add_theme_font_size_override("font_size", 13)
	_list.focus_mode = Control.FOCUS_NONE
	_list.tooltip_text = EditorIcons.tip("Solids nearby", "", "The solid boxes nearest the camera: number, kind, distance. Click one to select it\n(or click a box in the world); its fields show below.")
	_list.item_selected.connect(func(i): _select(int(_listed[i]) if i < _listed.size() else -1, false))
	add_child(_list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.add_child(_btn("Add", "add", "A new box: round what's picked if it's small, else in front of the camera.", _add))
	row.add_child(_btn("Copy", "duplicate", "A copy of the selected box, a metre over.", _duplicate))
	row.add_child(_btn("Delete", "delete", "The selected box gone.", _delete))
	add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	row2.add_child(_btn("Revert", "undo", "This place's solids as it builds them: its kept collision edits forgotten.", _revert))
	row2.add_child(_btn("Save", "save", "Keeps the edits (into the game, or the mod picked at the top).", _save))
	add_child(row2)
	add_child(LiveFields.head("SELECTED BOX"))
	_fields = VBoxContainer.new()
	_fields.add_theme_constant_override("separation", 4)
	add_child(_fields)
	_im = ImmediateMesh.new()
	_overlay = MeshInstance3D.new()
	_overlay.name = "SolidsOverlay"
	_overlay.mesh = _im
	_overlay.top_level = true
	_overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_overlay)   # (a 3D node under the tab: drawn in the game's world, gone with the tab)
	_load()
	_fill_fields()


func unbind() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	ed = null


func _btn(text: String, icon: String, help: String, cb: Callable) -> Button:
	var b := UI.button(text, cb, 14)
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	EditorIcons.dress(b, icon, EditorIcons.tip(text, "", help))
	b.text = text
	return b


# --- Its shapes ----------------------------------------------------------------------

func _load() -> void:
	if not is_instance_valid(_owner):
		return
	if not SolidsEdit.has_solids(_owner):
		_shapes = []
		_info.text = "%s: its solids aren't built yet (they come in as you near it)." % _owner.name
		return
	var keep := _sel
	_shapes = SolidsEdit.boxes(_owner)
	_sel = keep if keep < _shapes.size() else -1
	var off := _shapes.filter(func(s): return not bool(s.get("on", true))).size()
	_info.text = "%s - %d solid shapes%s. Click one in the world, or below (those within %d m)." % [
		_owner.name, _shapes.size() - off, (", %d off" % off) if off > 0 else "", int(REACH)]
	if _key == "":
		_info.text += " Not kept: this isn't a kind of thing the game makes again."
	_redraw = true
	_drawn_at = Vector3.INF


## The shapes changed: into the place at once, kept, redrawn.
func _apply() -> void:
	if not is_instance_valid(_owner):
		return
	SolidsEdit.set_boxes(_owner, _shapes)
	if _key != "":
		var rec := SolidsEdit.record(_owner)
		if rec.is_empty():
			LiveEdits.forget(_key, SolidsEdit.SECTION)
		else:
			rec["path"] = _rel
			var sec := LiveEdits.section(_key, SolidsEdit.SECTION)
			sec.clear()
			sec.merge(rec)
			LiveEdits.touched(_key)
	if ed:
		ed.edited(SolidsEdit.SECTION)
	_redraw = true
	_drawn_at = Vector3.INF


func _select(i: int, from_world := true) -> void:
	_sel = i
	_fill_fields()
	_redraw = true
	if from_world:
		_drawn_at = Vector3.INF   # (the list again, the picked row in it)


func _new_use() -> String:
	match SolidsEdit.kind_of(_owner):
		"hangar":
			return "both"
		"interior":
			return "walk"
	return ""


func _add() -> void:
	if not SolidsEdit.has_solids(_owner):
		return
	var inv := (_owner as Node3D).global_transform.affine_inverse()
	var s := {}
	var sel = ed.selected if ed else null
	if sel is Node3D and sel != _owner and ed.has_method("_aabb_of"):
		var g: AABB = ed.call("_aabb_of", sel)
		var l := inv * g
		if l.size != Vector3.ZERO and maxf(l.size.x, maxf(l.size.y, l.size.z)) < 40.0:
			s = SolidsEdit.make(l.get_center(), l.size * 0.5, Basis.IDENTITY, _new_use())
	if s.is_empty():
		var cam: Camera3D = ed.camera() if ed else null
		var at := Vector3.ZERO
		if cam:
			var fwd := inv.basis * -cam.global_basis.z
			fwd.y = 0.0
			at = inv * cam.global_position + (fwd.normalized() if fwd.length() > 0.01 else Vector3.ZERO) * 4.0
		s = SolidsEdit.make(at, Vector3(0.5, 1.0, 0.5), Basis.IDENTITY, _new_use())
	_shapes.append(s)
	_apply()
	_select(_shapes.size() - 1)
	_say("A box added: size it and move it below.")


func _duplicate() -> void:
	if _sel < 0 or _sel >= _shapes.size():
		_say("Pick a box first.")
		return
	var src: Dictionary = _shapes[_sel]
	var s: Dictionary
	if bool(src.get("ro", false)):   # (a sloped block: copied as a box round it)
		var b := SolidsEdit.bounds(src)
		s = SolidsEdit.make(b.get_center(), b.size * 0.5, Basis.IDENTITY, str(src.get("use", "")))
	else:
		s = src.duplicate()
		s.erase("src")
		s["id"] = -1
		s["ring"] = false
	var xf: Transform3D = s["xf"]
	xf.origin += xf.basis.x.normalized() * 1.0
	s["xf"] = xf
	_shapes.append(s)
	_apply()
	_select(_shapes.size() - 1)


func _delete() -> void:
	if _sel < 0 or _sel >= _shapes.size():
		_say("Pick a box first.")
		return
	_shapes.remove_at(_sel)
	_sel = -1
	_apply()
	_fill_fields()


func _revert() -> void:
	if not is_instance_valid(_owner):
		return
	SolidsEdit.revert(_owner)
	if _key != "":
		LiveEdits.forget(_key, SolidsEdit.SECTION)
	_sel = -1
	_load()
	_fill_fields()
	_say("As it's built: its collision edits forgotten.")


func _save() -> void:
	if ed and ed.has_method("save"):
		ed.save()
	elif LiveEdits.save():
		_say("Saved.")
	else:
		_say("Can't save here: pick a mod.")


func _say(t: String) -> void:
	if ed:
		ed.say(t)


# --- The selected box's fields -------------------------------------------------------

func _fill_fields() -> void:
	if _fields == null:
		return
	UI.clear(_fields)
	if _sel < 0 or _sel >= _shapes.size():
		_fields.add_child(UI.note("None: click a box in the world, or one in the list.", 13, 420.0))
		return
	var s: Dictionary = _shapes[_sel]
	var xf: Transform3D = s["xf"]
	var ro := bool(s.get("ro", false))
	_fields.add_child(UI.label("#%d  %s" % [_sel, _describe(s)], 14))
	_fields.add_child(LiveFields.row("Solid", bool(s.get("on", true)), func(v): _change(_sel, "on", v), "", "Off: the box stops nothing (kept, drawn grey) - a gap without deleting it."))
	if ro:
		_fields.add_child(UI.note("A sloped or many-sided block: it can be turned off, copied (as a box) or deleted, not moved.", 13, 420.0))
		return
	_fields.add_child(LiveFields.row("Centre (m)", xf.origin, func(v): _change(_sel, "centre", v), "", "The box's middle (metres), in the place's own frame."))
	var size: Vector3 = (s["half"] as Vector3) * 2.0
	_fields.add_child(LiveFields.row("Size (m)" if str(s["kind"]) != "cyl" else "Size (m: across, high)", size, func(v): _change(_sel, "size", v), "", "The box's size (metres): width, height, depth."))
	match _rot:
		"yaw":
			var bx := xf.basis.orthonormalized()
			_fields.add_child(LiveFields.row("Turn (degrees)", snappedf(rad_to_deg(atan2(-bx.x.z, bx.x.x)), 0.01), func(v): _change(_sel, "yaw", float(v)), "", "The box's turn about the upright (degrees)."))
		"full":
			var eu := xf.basis.orthonormalized().get_euler()
			_fields.add_child(LiveFields.row("Turn (degrees)", Vector3(rad_to_deg(eu.x), rad_to_deg(eu.y), rad_to_deg(eu.z)).snapped(Vector3.ONE * 0.01),
				func(v): _change(_sel, "euler", v), "", "The box's turn (degrees) about x, y and z."))
	if SolidsEdit.kind_of(_owner) == "hangar":
		var h := HBoxContainer.new()
		var l := UI.label("Stops", 13, UI.TEXT_DIM)
		l.custom_minimum_size.x = 150
		h.add_child(l)
		var ob := OptionButton.new()
		ob.add_theme_font_size_override("font_size", 13)
		ob.focus_mode = Control.FOCUS_NONE
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for i in USES.size():
			ob.add_item(USES[i][1])
			if USES[i][0] == str(s.get("use", "both")):
				ob.select(i)
		ob.tooltip_text = EditorIcons.tip("Stops", "", "What the box stops: the camera (it never passes through), feet (you walking), or both.")
		l.tooltip_text = ob.tooltip_text
		ob.item_selected.connect(func(i): _change(_sel, "use", USES[i][0]))
		h.add_child(ob)
		_fields.add_child(h)
	if SolidsEdit.kind_of(_owner) in ["hangar", "interior"]:
		_fields.add_child(UI.note("Feet: only its footprint counts (its height is drawn, not used).", 13, 420.0))


func _change(i: int, what: String, v: Variant) -> void:
	if i < 0 or i >= _shapes.size():
		return
	var s: Dictionary = _shapes[i]
	var xf: Transform3D = s["xf"]
	match what:
		"on":
			s["on"] = bool(v)
		"use":
			s["use"] = str(v)
		"centre":
			xf.origin = v
		"size":
			var sz: Vector3 = (v as Vector3).abs()
			s["half"] = Vector3(maxf(sz.x, 0.02), maxf(sz.y, 0.02), maxf(sz.z, 0.02)) * 0.5
		"yaw":
			xf.basis = Basis(Vector3.UP, deg_to_rad(float(v)))
		"euler":
			var e: Vector3 = v
			xf.basis = Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
	s["xf"] = xf
	_apply()
	_list_row(i)


func _describe(s: Dictionary) -> String:
	var sz: Vector3 = (s["half"] as Vector3) * 2.0
	var turned := not (s["xf"] as Transform3D).basis.is_equal_approx(Basis.IDENTITY)
	var t := "%s%s  %.1f x %.1f x %.1f m" % ["turned " if turned and str(s["kind"]) != "prism" else "", KINDS.get(str(s["kind"]), "box"), sz.x, sz.y, sz.z]
	var use := str(s.get("use", ""))
	if use == "cam":
		t += "  (camera)"
	elif use == "walk":
		t += "  (feet)"
	if not bool(s.get("on", true)):
		t += "  - off"
	return t


# --- The world: picking, the lines ---------------------------------------------------

## A click in the world (global ray): the nearest box it meets selected - true
## when there was one (else the editor picks as usual).
func pick_in_world(origin: Vector3, dir: Vector3) -> bool:
	if not is_instance_valid(_owner) or _shapes.is_empty():
		return false
	var inv := (_owner as Node3D).global_transform.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	var best := INF
	var bi := -1
	for i in _shapes.size():
		var t := SolidsEdit.ray(_shapes[i], o, d, minf(best, 2000.0))
		if t < best:
			best = t
			bi = i
	if bi < 0:
		return false
	_select(bi)
	_say("Box #%d: %s" % [bi, _describe(_shapes[bi])])
	return true


func live_process(delta: float) -> void:
	if ed == null:
		return
	if not is_instance_valid(_owner):
		if _overlay:
			_im.clear_surfaces()
		return
	_overlay.global_transform = (_owner as Node3D).global_transform
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		if SolidsEdit.has_solids(_owner) and (_shapes.is_empty() or not SolidsEdit.current(_owner)):
			_load()   # (built since, or built again: its solids anew)
			_fill_fields()
		var cl := _cam_local()
		if cl.distance_to(_drawn_at) > 3.0:
			_drawn_at = cl
			_redraw = true
			_fill_list(cl)
	if _redraw:
		_redraw = false
		_draw_lines(_cam_local())


func _cam_local() -> Vector3:
	var cam: Camera3D = ed.camera() if ed else null
	if cam == null or not is_instance_valid(_owner):
		return Vector3.ZERO
	return (_owner as Node3D).to_local(cam.global_position)


func _fill_list(cl: Vector3) -> void:
	var near: Array = []
	for i in _shapes.size():
		var d := SolidsEdit.distance(_shapes[i], cl)
		if d < REACH or i == _sel:
			near.append([d, i])
	near.sort_custom(func(a, b): return a[0] < b[0])
	_list.clear()
	_listed.clear()
	for e in near.slice(0, LISTED):
		var i: int = e[1]
		_list.add_item("#%d  %s   %.0f m" % [i, _describe(_shapes[i]), float(e[0])])
		_listed.append(i)
		if i == _sel:
			_list.select(_list.item_count - 1)
	if _sel >= 0 and _listed.has(_sel):
		_list.ensure_current_is_visible()


func _list_row(i: int) -> void:
	var r := _listed.find(i)
	if r >= 0:
		var cl := _cam_local()
		_list.set_item_text(r, "#%d  %s   %.0f m" % [i, _describe(_shapes[i]), SolidsEdit.distance(_shapes[i], cl)])


func _draw_lines(cl: Vector3) -> void:
	_im.clear_surfaces()
	if _shapes.is_empty():
		return
	_overlay.material_override = _material(_xray.button_pressed)
	var any := false
	for i in _shapes.size():
		var s: Dictionary = _shapes[i]
		if i != _sel and SolidsEdit.distance(s, cl) > REACH:
			continue
		if not any:
			_im.surface_begin(Mesh.PRIMITIVE_LINES)
			any = true
		var col := C_SOLID
		if i == _sel:
			col = C_SEL
		elif not bool(s.get("on", true)):
			col = C_OFF
		elif str(s.get("use", "")) == "walk":
			col = C_FEET
		elif str(s.get("use", "")) == "cam":
			col = C_CAM
		_box_lines(s, col, i == _sel)
	if any:
		_im.surface_end()


func _box_lines(s: Dictionary, col: Color, sel: bool) -> void:
	var xf: Transform3D = s["xf"]
	var h: Vector3 = s["half"]
	var c: Array = []
	for k in 8:
		c.append(xf * Vector3(h.x if k & 1 else -h.x, h.y if k & 2 else -h.y, h.z if k & 4 else -h.z))
	_im.surface_set_color(col)
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		_im.surface_add_vertex(c[e[0]])
		_im.surface_add_vertex(c[e[1]])
	if sel:   # (the picked one: its faces crossed too)
		for e in [[0, 3], [4, 7], [0, 6], [1, 7], [0, 5], [2, 7]]:
			_im.surface_add_vertex(c[e[0]])
			_im.surface_add_vertex(c[e[1]])


static func _material(xray: bool) -> StandardMaterial3D:
	if (_mat_xray if xray else _mat_depth) == null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.vertex_color_use_as_albedo = true
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = xray
		m.render_priority = 10
		if xray:
			_mat_xray = m
		else:
			_mat_depth = m
	return _mat_xray if xray else _mat_depth
