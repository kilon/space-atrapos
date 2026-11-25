extends VBoxContainer
## The mesh editor's SHAPE panel (in its right panel): the parameters of a shape -
## the one picked in the shape browser (with a preview of it, turning while the
## mouse is on it), or the selected part's when it was made from a shape (the part
## made again as they change) - each a field and a slider. Its buttons: add the
## picked shape to the model, save these parameters (or the part's mesh) as a new
## shape, rename or delete a shape of the library.

signal param_changed(key: String, value: float, final: bool)
signal add_requested
signal save_requested
signal rename_requested
signal delete_requested

const Shapes := preload("res://scripts/editor/mesh/shapes.gd")

## "library" (a picked shape), "part" (the selected part's), "mesh" (a part without a recipe), "" (nothing).
var mode := ""
var gen := ""
var params := {}
var _title: Label
var _fields: VBoxContainer
var _pv_box: SubViewportContainer
var _pv: SubViewport
var _pv_cam: Camera3D
var _pv_pivot: Node3D
var _pv_mi: MeshInstance3D
var _btns := {}
var _syncing := false
var _hover := false
var _t := 0.0
var _shown_t := -1.0


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	_title = UI.label("Pick a shape in the Shapes tab (left), or select a part made from one.", 14, UI.TEXT_DIM)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size.x = 180
	add_child(_title)
	_build_preview()
	_fields = VBoxContainer.new()
	_fields.add_theme_constant_override("separation", 2)
	add_child(_fields)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	add_child(row)
	for b in [["add", "m_shape_add", "Add to model", "", "Adds the picked shape to the model as a new part (or double-click it in the Shapes tab,\nor drag it into the view)."],
			["save", "m_shape_save", "Save as new shape", "", "Keeps these parameters - or, for a part not made from a shape, the part's mesh itself -\nas a new shape of the library (with a name and a category), saved with the game or your mod."],
			["rename", "rename", "Rename shape", "", "Renames the picked shape or moves it to another category."],
			["delete", "delete", "Remove shape", "", "Removes the picked shape from the library (one of the 120 built in: asks first)."]]:
		var btn := UI.button("", func(): pass, 14)
		btn.focus_mode = Control.FOCUS_NONE
		EditorIcons.dress(btn, b[1], EditorIcons.tip(b[2], b[3], b[4]), "Add" if b[0] == "add" else ("Save" if b[0] == "save" else ""))
		btn.text = ""   # (icons only: compact)
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.custom_minimum_size = Vector2(32, 30)
		btn.name = "Shape_" + b[0]
		var sig: Signal = {"add": add_requested, "save": save_requested, "rename": rename_requested, "delete": delete_requested}[b[0]]
		btn.pressed.connect(func(): sig.emit())
		_btns[b[0]] = btn
		row.add_child(btn)
	show_shape("", "", "", {})


func _build_preview() -> void:
	_pv_box = SubViewportContainer.new()
	_pv_box.stretch = true
	_pv_box.custom_minimum_size = Vector2(180, 140)
	_pv_box.mouse_entered.connect(func(): _hover = true)
	_pv_box.mouse_exited.connect(func(): _hover = false)
	_pv_box.tooltip_text = EditorIcons.tip("Shape preview", "", "The picked shape as its parameters make it (it turns while the mouse is on it).")
	add_child(_pv_box)
	_pv = SubViewport.new()
	_pv.own_world_3d = true
	_pv.transparent_bg = true
	_pv.msaa_3d = Viewport.MSAA_4X
	_pv.render_target_update_mode = SubViewport.UPDATE_ONCE
	_pv_box.add_child(_pv)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_pv.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.6
	_pv.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	_pv.add_child(rim)
	_pv_cam = Camera3D.new()
	_pv_cam.fov = 35.0
	_pv.add_child(_pv_cam)
	_pv_pivot = Node3D.new()
	_pv.add_child(_pv_pivot)
	_pv_mi = MeshInstance3D.new()
	_pv_pivot.add_child(_pv_mi)


## Shows shape `gen` with `params`: `m` "library" / "part" / "mesh" / "" (nothing), `title` above it.
func show_shape(m: String, title: String, g: String, p: Dictionary, can_delete := true) -> void:
	mode = m
	gen = g
	params = Shapes.full_params(g, p) if g != "" and g != "mesh" else p.duplicate()
	_title.text = title if title != "" else "Pick a shape in the Shapes tab (left), or select a part made from one."
	_title.add_theme_color_override("font_color", NeonTheme.HEAD if m != "" else UI.TEXT_DIM)
	_pv_box.visible = m == "library"
	for c in _fields.get_children():
		c.queue_free()
	if g != "" and g != "mesh":
		for spec in Shapes.GENS[g]["params"]:
			_field(spec)
	elif m == "mesh" or g == "mesh":
		pass   # (a mesh of its own: no parameters - the title says so)
	(_btns["add"] as Button).disabled = m != "library"
	(_btns["save"] as Button).disabled = m == "" or not EditTarget.writable()
	(_btns["rename"] as Button).disabled = m != "library" or not EditTarget.writable()
	(_btns["delete"] as Button).disabled = m != "library" or not can_delete or not EditTarget.writable()


func _field(spec: Array) -> void:
	var key: String = spec[0]
	var whole := float(spec[4]) >= 1.0 and float(spec[2]) == floorf(float(spec[2]))
	var head := HBoxContainer.new()
	var l := UI.label(spec[1], 13, UI.TEXT_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.clip_text = true
	head.add_child(l)
	var sb := SpinBox.new()
	sb.name = "Param_" + key
	sb.min_value = spec[2]
	sb.max_value = spec[3]
	sb.step = spec[4]
	sb.allow_greater = not whole
	sb.allow_lesser = false
	sb.rounded = whole
	sb.custom_minimum_size.x = 84
	sb.add_theme_font_size_override("font_size", 13)
	sb.get_line_edit().add_theme_font_size_override("font_size", 13)
	sb.set_value_no_signal(float(params.get(key, spec[5])))
	sb.tooltip_text = EditorIcons.tip(spec[1], "", "The shape's %s (%s to %s)." % [str(spec[1]).to_lower(), str(spec[2]), str(spec[3])])
	head.add_child(sb)
	_fields.add_child(head)
	var sl := HSlider.new()
	sl.min_value = spec[2]
	sl.max_value = spec[3]
	sl.step = spec[4]
	sl.rounded = whole
	sl.focus_mode = Control.FOCUS_NONE
	sl.custom_minimum_size.y = 16
	sl.set_value_no_signal(clampf(float(params.get(key, spec[5])), spec[2], spec[3]))
	sl.tooltip_text = sb.tooltip_text
	_fields.add_child(sl)
	sb.value_changed.connect(func(v):
		if _syncing:
			return
		_syncing = true
		sl.set_value_no_signal(clampf(v, sl.min_value, sl.max_value))
		_syncing = false
		params[key] = v
		param_changed.emit(key, v, true))
	sl.value_changed.connect(func(v):
		if _syncing:
			return
		_syncing = true
		sb.set_value_no_signal(v)
		_syncing = false
		params[key] = v
		param_changed.emit(key, v, false))
	sl.drag_ended.connect(func(changed):
		if changed:
			param_changed.emit(key, sl.value, true))


## Sets a parameter as if typed (tests, scripts).
func set_param(key: String, v: float) -> void:
	var sb := _fields.find_child("Param_" + key, true, false) as SpinBox
	if sb:
		sb.value = v


## The preview shows `mesh` (made elsewhere, on a worker).
func set_preview(mesh: Mesh) -> void:
	_pv_mi.mesh = mesh
	if mesh == null:
		return
	if mesh.get_surface_count() > 0 and mesh.surface_get_material(0) == null:
		_pv_mi.material_override = preload("res://scripts/editor/mesh/mesh_io.gd").preset(4)
	var box := mesh.get_aabb()
	_pv_mi.position = -box.get_center()
	var r := maxf(box.size.length() * 0.5, 0.05)
	var dir := Vector3(0.55, 0.35, 1.0).normalized()
	var dist := r / sin(deg_to_rad(_pv_cam.fov * 0.5)) * 1.05
	_pv_cam.look_at_from_position(dir * dist, Vector3.ZERO, Vector3.UP)
	_pv_cam.near = maxf(dist * 0.01, 0.001)
	_pv_cam.far = dist * 4.0
	_pv.render_target_update_mode = SubViewport.UPDATE_ONCE


## (The preview turns while the mouse is on it: redrawn 30 times a second, by the clock.)
func _process(dt: float) -> void:
	if not _hover or not _pv_box.visible or _pv_mi.mesh == null:
		return
	_t += dt
	if _t - _shown_t < 1.0 / 30.0:
		return
	_shown_t = _t
	_pv_pivot.rotation.y = _t * 0.9
	_pv.render_target_update_mode = SubViewport.UPDATE_ONCE
