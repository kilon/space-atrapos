extends Control
## Talos's mesh editor (Meshes, F6): the game's models and your own - their
## parts, moved, rotated, scaled, added from primitives; a part's vertices,
## edges and faces in edit mode (Tab) with proportional editing, symmetry and
## a mirror modifier; its surfaces' materials. Saves glb (GLTFDocument) where
## EditTarget says - the game, or the mod being made - keeping a character's
## skeleton, skin and animations.
##
## The pieces: mesh/edit_mesh.gd (a part's editable copy: welded points over
## the vertex arrays, the edits), mesh/mesh_view.gd (the 3D view, camera,
## overlays), mesh/mesh_io.gd (files, primitives, materials).
## Embedded (the Mod Editor: `embedded = true` before it enters the tree):
## no Talos rail, and Esc doesn't leave.

const EditMesh := preload("res://scripts/editor/mesh/edit_mesh.gd")
const MeshView := preload("res://scripts/editor/mesh/mesh_view.gd")
const MeshIO := preload("res://scripts/editor/mesh/mesh_io.gd")
const ShapeTools := preload("res://scripts/editor/mesh/shape_tools.gd")
const MaterialTools := preload("res://scripts/editor/mesh/material_tools.gd")
const MeshOps := preload("res://scripts/editor/mesh/mesh_ops.gd")
const DeformTools := preload("res://scripts/editor/mesh/deform_tools.gd")
const RefImages := preload("res://scripts/editor/mesh/ref_images.gd")
const CurveTools := preload("res://scripts/editor/mesh/curve_tools.gd")
const ACCENT := Color(1.0, 0.72, 0.38)
const KINDS := ["Vertex", "Edge", "Face"]
## Over this many vertices a part's edit mode is prepared on a worker thread.
const BIG := 6000

var embedded := false
var dirty := false
## The open model's res:// path ("": not saved yet).
var path := ""
var model: Node3D
var part: MeshInstance3D
var mode := "object"
var em = null                       # EditMesh while in edit mode
var sel_kind := 3                   # 0 vertex, 1 edge, 2 face, 3 Auto (by where you click: the default)
var sel_p := PackedByteArray()
var sel_e := PackedByteArray()
var sel_t := PackedByteArray()
var prop_on := false
var prop_falloff := "smooth"
var prop_radius := 0.5
var prop_connected := false
var sym := [false, false, false]
var loading := false
var view: MeshView
## The transform being dragged ({} - none).
var xf := {}
## Undo: [{name, undo, redo}] for the model, and one for edit mode's edits.
var _undo: Array = []
var _redo: Array = []
var _eundo: Array = []
var _eredo: Array = []
const UNDO_MAX := 80
const UNDO_BYTES := 200 << 20

var _note: Label
var _files: ItemList
var _filter: LineEdit
var _all_files := PackedStringArray()
var _parts: Tree
var _fields := {}
var _mode_btn: Button
var _kind_btns: Array = []
var _prop_btn: Button
var _falloff: OptionButton
var _radius: SpinBox
var _connected: Button
var _sym_btns: Array = []
var _mirror := {}
var _mat := {}
var _save_btn: Button
var _edit_box: Control
var _syncing := false
var _mouse := Vector2.ZERO
var _press := Vector2(-1, -1)
var _drag := ""
var _task := -1
var _task_out: Array = []
var _task_kind := ""
var _task_part: MeshInstance3D
var _scan_task := -1
var _scan_out: Array = []
var _ghosts := {}                   # part -> [MeshInstance3D]
var _em_tm: TriangleMesh
var _part_mesh_before: Mesh         # the part's mesh when edit mode began
var _refill := false
var _art_ok := ""                   # (a character you agreed to save over)
var _model_mats: Array = []
var _tpose_btn: Button
var _revert_btn: Button
var variant := 0                     # the open variant of its override (0 - the original)
var _pending_variant := 0            # (the variant being opened)
var _variants: Array = []            # the open model's variants (ModelOverride.variants)
var _variant_opt: OptionButton
var _variant_btns: Array = []        # add, duplicate, erase
## The parts selected (Ctrl / Shift+click adds), in the order picked; `part` is the last (the active one).
var sel_parts: Array = []
## The part that was selected when another was right-clicked (a boolean's A).
var _menu_prev: MeshInstance3D
## The shape library, its browser and panel, the booleans (mesh/shape_tools.gd).
var shape_tools: ShapeTools
var mat_tools: MaterialTools
## Duplicate, merge by distance, inset, loop cut, select loop / ring (mesh/mesh_ops.gd).
var mesh_ops: MeshOps
var deform: DeformTools   # (curve deform, flatten: deform_tools.gd)
var ref_images: RefImages   # (the view's reference images: ref_images.gd)
var curve_tools: CurveTools   # (the Curve modeling tab: sketched curves made into solids - curve_tools.gd)
var _right_tabs: TabContainer
var _menu_tab := 0   # (the right-click menu's tab: 0 Mesh, 1 Curve modeling)
var left_tab := "models"
var _models_box: VBoxContainer
var _tab_btns := {}
var _outlined_more: Array = []
var _weapons_btn: Button         # the open model's own materials


func _ready() -> void:
	_build()
	new_model(true)
	_say("Double-click a model on the left to open it, or add solids from the panel on the right.")
	_start_scan()


func _exit_tree() -> void:
	for e in (get_meta("tip_models", {}) as Dictionary).values():
		if int(e[0]) >= 0:
			WorkerThreadPool.wait_for_task_completion(int(e[0]))   # (a model read for a tooltip: never left running)
			e[1] = (e[2] as Array)[0]
		if e[1] is Node and is_instance_valid(e[1]) and not (e[1] as Node).is_inside_tree():
			(e[1] as Node).free()
	remove_meta("tip_models")
	for t in [_task, _scan_task, _tpose_task, _tm_task]:
		if t >= 0:
			WorkerThreadPool.wait_for_task_completion(t)
	# (a drop being read, a store's weights or its writing: waited for - never left running)
	if has_meta("drop_job"):
		WorkerThreadPool.wait_for_task_completion(int(get_meta("drop_job")[0]))
	if has_meta("store_job"):
		WorkerThreadPool.wait_for_task_completion(int(get_meta("store_job")["weighted"][0]))
	if has_meta("store_write"):
		WorkerThreadPool.wait_for_task_completion(int(get_meta("store_write")[0]))
	_task = -1
	_scan_task = -1
	_tm_task = -1
	_drop_entries(_undo + _redo)


func _notification(what: int) -> void:
	if view == null:
		return
	if what == NOTIFICATION_DISABLED:
		view.set_off(true)   # (Talos shows another tool: no rendering)
	elif what == NOTIFICATION_ENABLED:
		view.set_off(false)


## Talos shows the editor again.
## What it had open, to come back to after a live rebuild (LiveLink): the model's path, the part.
func live_state() -> Dictionary:
	return {"path": path, "part": str(part.name) if part and is_instance_valid(part) else ""}


func live_restore(st: Dictionary) -> void:
	if str(st.get("path", "")) != "" and open_now(str(st["path"])):
		for p in parts():
			if str(p.name) == str(st.get("part", "")):
				select_part(p)
		frame_all()
	_say("Live update: the ECurves editor built again with the new code.")


func talos_shown() -> void:
	view.set_off(false)
	_start_scan()


# --- building the screen ------------------------------------------------------------

func _build() -> void:
	var col: VBoxContainer
	if embedded:
		col = VBoxContainer.new()
		col.set_anchors_preset(Control.PRESET_FULL_RECT)
		col.add_theme_constant_override("separation", 4)
		add_child(col)
	else:
		col = TalosNav.wrap(UI.modal(self, ACCENT, Vector2.ZERO, true), "mesh", func(id): TalosNav.go(get_tree(), id, guard))
	shape_tools = ShapeTools.new()
	add_child(shape_tools)
	shape_tools.setup(self)
	mat_tools = MaterialTools.new()
	add_child(mat_tools)
	mat_tools.setup(self)
	mesh_ops = MeshOps.new()
	add_child(mesh_ops)
	mesh_ops.setup(self)
	deform = DeformTools.new()
	add_child(deform)
	deform.setup(self)
	ref_images = RefImages.new()
	add_child(ref_images)
	ref_images.setup(self)
	curve_tools = CurveTools.new()
	add_child(curve_tools)
	curve_tools.setup(self)
	var hn := TalosNav.header("ECURVES", "", ACCENT)
	var header: HBoxContainer = hn[0]
	_note = hn[1]
	header.add_child(_btn("New model", "new", "Ctrl+N", "An empty model: add primitives to it (the panel on the right).", func(): _ask_unsaved(func(): new_model())))
	header.add_child(_btn("Import from disk", "open", "Ctrl+O", "Opens a .glb, .gltf or .obj file from anywhere on this computer (save it into the game or your mod with Save as).", _import))
	_save_btn = _btn("Save", "save", "Ctrl+S", "Saves the model as glb where it was opened from (into your mod, in the Mod Editor).\nMirror modifiers are applied into the saved meshes; skeleton, skin and animations are kept.", func(): save())
	header.add_child(_save_btn)
	header.add_child(_btn("Save as", "export", "Ctrl+Shift+S", "Saves the model under another res:// path (as glb).", save_as))
	_revert_btn = _btn("Revert to original", "m_revert", "", "Deletes your saved changes to this model (its override) and opens the original again.\nSaving never writes over the original: it's kept, and the game uses your version until you revert.", func(): revert_to_original())
	header.add_child(_revert_btn)
	_variant_opt = OptionButton.new()
	_variant_opt.focus_mode = Control.FOCUS_NONE
	_variant_opt.fit_to_longest_item = false
	_variant_opt.custom_minimum_size.x = 150
	_variant_opt.add_theme_font_size_override("font_size", 14)
	_variant_opt.tooltip_text = "Variants: versions of your override of this model.\nThe latest is the active one - the game uses it. Pick one to open it (Original: the game's own, kept as it was)."
	_variant_opt.item_selected.connect(func(i): open_variant(_variant_opt.get_item_id(i)))
	header.add_child(_variant_opt)
	_variant_btns = [
		_btn("Add variant", "add", "", "A new variant of this model, starting from the original - the latest, so the game uses it.\nSave to keep your edits in it.", func(): add_variant()),
		_btn("Duplicate variant", "duplicate", "", "A copy of the open variant (with your unsaved edits) as a new variant - the latest, so the game uses it.\nAn older variant duplicated becomes the active one again.", func(): duplicate_variant()),
		_btn("Erase variant", "delete", "", "Deletes the open variant (asks first). If it was the latest, the one before it becomes active; none left - the original.", func(): erase_variant())]
	for b in _variant_btns:
		header.add_child(b)
	header.add_child(_btn("Undo", "undo", "Ctrl+Z", "Takes back the last edit (in edit mode: the last edit of the solid's mesh).", undo))
	header.add_child(_btn("Redo", "redo", "Ctrl+Y", "Does again what Undo took back.", redo))
	header.add_child(EditorIcons.docs_button(self, "mesh"))
	col.add_child(header)
	_header = header
	_col = col

	# The panels: models and parts | the view | the part's panel - each split dragged to any size
	# (the sizes kept: user://editor_layout.cfg).
	var body := _split("body", false)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)
	_left_panel = _build_left()
	body.add_child(_left_panel)
	var rest := _split("rest", false)
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(rest)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 3)
	rest.add_child(mid)
	_build_toolbar(mid)
	_right_btn = _panel_toggle("m_panel_right", "Right panel", "Ctrl+]", "Shows or hides the right panel (the solid, edit mesh, booleans, shapes, mirror, material).", func(): set_right_panel(not right_shown))
	# (the panels' toggles: in the view's corner, under its maximise button)
	view = MeshView.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.custom_minimum_size = Vector2(320, 240)
	view.tooltip_text = ""
	view.clip_contents = true   # (its lines - an axis, the gizmo, the knife - kept inside the view)
	view.gui_input.connect(_view_input)
	view.set_drag_forwarding(Callable(), _can_drop_shape, _drop_shape)   # (a shape dragged in from the Shapes tab)
	view.mouse_exited.connect(func():
		_mouse = view.size * 0.5
		if _focus != Vector3.INF and _drag == "" and xf.is_empty():
			_focus = Vector3.INF
			_overlays())
	mid.add_child(view)
	curve_tools.attach(view)
	# the view's maximise button, in its top-right corner
	_max_btn = Button.new()
	_max_btn.icon = EditorIcons.get_icon("m_maximize")
	_max_btn.focus_mode = Control.FOCUS_NONE
	_max_btn.tooltip_text = EditorIcons.tip("Maximise the view", "Ctrl+M", "The 3D view fills the screen: the side panels, the toolbar and Talos's header and rail hidden.\nAgain: everything back.")
	_max_btn.anchor_left = 1.0
	_max_btn.anchor_right = 1.0
	_max_btn.offset_left = -40
	_max_btn.offset_right = -6
	_max_btn.offset_top = 6
	_max_btn.offset_bottom = 38
	_max_btn.pressed.connect(func(): set_maximized(not maximized))
	IconAnim.attach(_max_btn, "m_maximize")
	view.add_child(_max_btn)
	for i in 2:
		var b: Button = [_left_btn, _right_btn][i]
		b.anchor_left = 1.0
		b.anchor_right = 1.0
		b.offset_left = -40
		b.offset_right = -6
		b.offset_top = 42 + i * 36
		b.offset_bottom = 74 + i * 36
		view.add_child(b)
	_right_panel = _build_right()
	rest.add_child(_right_panel)
	UI.scale_fonts(col, "menu", 1.0)
	hide_menu_twins()
	_update_ui()
	_load_layout.call_deferred()


const LAYOUT := "user://editor_layout.cfg"
var _splits := {}       # name -> SplitContainer


## A split (`vertical`: one above the other) whose divider is dragged to resize its two sides.
func _split(name: String, vertical: bool) -> SplitContainer:
	var sp: SplitContainer = VSplitContainer.new() if vertical else HSplitContainer.new()
	sp.name = "Split_" + name
	sp.add_theme_constant_override("separation", 6)
	sp.dragger_visibility = SplitContainer.DRAGGER_VISIBLE
	sp.tooltip_text = ""
	sp.dragged.connect(func(_o): _split_dragged(name))
	_splits[name] = sp
	return sp


## A divider dragged: a side panel pulled well past its smallest size collapses (as its toolbar
## toggle does - which brings it back); otherwise the sizes are kept.
const COLLAPSE_PAST := 48.0


func _split_dragged(name: String) -> void:
	var mx := get_global_mouse_position().x
	if name == "body" and _left_panel and _left_panel.visible:
		var want := mx - _left_panel.global_position.x
		if want < _left_panel.get_combined_minimum_size().x - COLLAPSE_PAST:
			set_left_panel(false)
			return
	elif name == "rest" and _right_panel and _right_panel.visible:
		var want := _right_panel.global_position.x + _right_panel.size.x - mx
		if want < _right_panel.get_combined_minimum_size().x - COLLAPSE_PAST:
			set_right_panel(false)
			return
	_save_layout()


func _load_layout() -> void:
	var c := ConfigFile.new()
	c.load(LAYOUT)
	set_list_view(str(c.get_value("mesh", "list_view", "icons")))
	gizmo_on = bool(c.get_value("mesh", "gizmo", false))
	move_mode = str(c.get_value("mesh", "move_mode", "smart"))
	for k in _move_btns:
		(_move_btns[k] as Button).set_pressed_no_signal(k == move_mode)
	left_shown = bool(c.get_value("mesh", "left_shown", true))
	right_shown = bool(c.get_value("mesh", "right_shown", true))
	_apply_panels()
	if _gizmo_btn:
		_gizmo_btn.set_pressed_no_signal(gizmo_on)
	_sync_gizmo()
	set_left_tab(str(c.get_value("mesh", "left_tab", "models")))
	if not c.has_section_key("mesh", "left") and _splits.has("left"):
		(_splits["left"] as SplitContainer).split_offset = 260   # (at first: the models list the taller - few parts)
	for n in _splits:
		if c.has_section_key("mesh", n):
			(_splits[n] as SplitContainer).split_offset = int(c.get_value("mesh", n))


func _save_layout() -> void:
	var c := ConfigFile.new()
	c.load(LAYOUT)
	for n in _splits:
		c.set_value("mesh", n, (_splits[n] as SplitContainer).split_offset)
	c.save(LAYOUT)


## An icon button (its name, keys and help in its tooltip - no words on it: a compact screen).
func _btn(name: String, icon: String, keys: String, help: String, cb: Callable) -> Button:
	var b := UI.button("", cb, 14)
	b.focus_mode = Control.FOCUS_NONE
	EditorIcons.dress(b, icon, EditorIcons.tip(name, keys, help))
	return _compact(b)


## The tool buttons' icons, by their name (the rest keep their word).
const ICON_OF := {"Vertex": "m_vertex", "Edge": "m_edge", "Face": "m_face", "Front": "m_front", "Side": "m_side", "Top": "m_top",
	"Ortho": "m_ortho", "Frame": "m_frame", "T-pose": "m_tpose", "Weapons": "m_weapons", "X": "m_sym_x", "Y": "m_sym_y", "Z": "m_sym_z",
	"Symmetrize": "m_symmetrize", "Symmetrize topology": "m_symmetrize_topo", "Apply": "m_mirror_apply", "Box": "m_box", "Cylinder": "m_cylinder", "Cone": "m_cone",
	"Sphere": "m_sphere", "Plane": "m_plane", "Torus": "m_torus", "Extrude": "m_extrude", "Delete": "delete", "Merge": "m_merge",
	"Subdivide": "m_subdivide", "Dissolve": "m_dissolve", "Flip normals": "m_flip", "Recalc normals": "m_normals", "Select all": "m_sel_all",
	"Object mode": "m_object", "Edit mode": "m_edit", "Material island": "m_sel_material", "Spherize": "m_spherize", "Curve deform": "m_curve", "Flatten": "m_flatten"}


func _small(text: String, tip: String, cb: Callable, toggle := false) -> Button:
	var b := UI.button(text, cb, 14)
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = toggle
	b.tooltip_text = tip
	if ICON_OF.has(text):
		b.icon = EditorIcons.get_icon(ICON_OF[text])
		b.text = ""
		IconAnim.attach(b, ICON_OF[text])
		_compact(b)
	return b


func _compact(b: Button) -> Button:
	b.text = ""
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.custom_minimum_size = Vector2(32, 30)
	return b


func _build_left() -> Control:
	var split := _split("left", true)
	split.custom_minimum_size.x = 160
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 160
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 3)
	split.add_child(left)
	var lower := VBoxContainer.new()
	lower.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lower.add_theme_constant_override("separation", 3)
	split.add_child(lower)
	var mh := HBoxContainer.new()
	for t in [["models", "mesh", "Models", "The game's models (the characters, art/*_3d/, first) and every .glb, .gltf, .obj and mesh resource\nin the game (and your mod) - and yours. Double-click one to open it; hover one: its picture, big."],
			["shapes", "m_shapes", "Primitives", "The primitive solids of ECurve objects - box, cylinder, prism, cone, sphere, torus: double-click\none to add it, or drag it into the view. Each is made of its edges: reshape them and it follows."],
			["materials", "m_materials", "Material library", "Every material: the open model's, the characters', the game's looks and your own, as balls.\nClick one to edit it (the MATERIAL panel), double-click it to give it to the selected surface\nor faces, or drag it onto a surface in the view.", "Materials"]]:
		var tb := UI.button("", func(): pass, 14)
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		EditorIcons.dress(tb, t[1], EditorIcons.tip(t[2], "", t[3]), t[4] if t.size() > 4 else t[2])
		tb.name = "Tab_" + t[0]
		tb.pressed.connect(func(): set_left_tab(t[0]))
		_tab_btns[t[0]] = tb
		mh.add_child(tb)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(gap)
	for v in [["icons", "m_icons", "Icons", "Every model as a picture of it (drawn once, in the background)."],
			["details", "m_list", "Details", "Every model by its path, with a small picture."]]:
		var b := Button.new()
		b.icon = EditorIcons.get_icon(v[1])
		IconAnim.attach(b, v[1])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = EditorIcons.tip(v[2], "", v[3])
		b.name = "View_" + v[0]
		b.pressed.connect(func(): set_list_view(v[0]))
		_view_btns[v[0]] = b
		mh.add_child(b)
	left.add_child(mh)
	_filter = LineEdit.new()
	_filter.placeholder_text = "Find a model..."
	_filter.add_theme_font_size_override("font_size", 14)
	_filter.text_changed.connect(func(_t): _fill_files())
	_filter.tooltip_text = EditorIcons.tip("Find a model", "", "Narrows the list to the files whose path has these words.")
	_models_box = VBoxContainer.new()
	_models_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_models_box.add_theme_constant_override("separation", 3)
	left.add_child(_models_box)
	_models_box.add_child(_filter)
	_files = ItemList.new()
	_files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_files.focus_mode = Control.FOCUS_NONE
	_files.add_theme_font_size_override("font_size", 14)
	_files.tooltip_text = ""   # (the list's own tooltip: on its tab - over the list, each model's own)
	_files.set_meta("tip_on_tab", "models")
	_files.item_activated.connect(func(i): open(str(_files.get_item_metadata(i))))
	_files.item_selected.connect(func(i): fill_variant_browser(str(_files.get_item_metadata(i))))
	_files.set_drag_forwarding(_drag_model, Callable(), Callable())   # (an ECurve object dragged into the view: added there)
	_models_box.add_child(_files)
	shape_tools.browser.visible = false
	left.add_child(shape_tools.browser)
	var prims: Control = load("res://scripts/editor/mesh/primitive_browser.gd").new()
	prims.name = "PrimitiveBrowser"
	prims.visible = false
	prims.set("ct", curve_tools)
	left.add_child(prims)
	set_meta("prims", prims)
	mat_tools.browser.visible = false
	left.add_child(mat_tools.browser)
	lower.add_child(EditorIcons.tipped(UI.section("VARIANTS"), EditorIcons.tip("Variants", "double-click", "The variants of the ECurve object picked above (or the open one): the original and each saved\nvariant (the latest is the one the game uses). Double-click one to open it.")))
	var vb := ItemList.new()
	vb.name = "VariantBrowser"
	vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.custom_minimum_size.y = 80
	vb.focus_mode = Control.FOCUS_NONE
	vb.add_theme_font_size_override("font_size", 14)
	vb.tooltip_text = EditorIcons.tip("Variants", "double-click", "Double-click a variant to open it.")
	vb.item_activated.connect(func(i):
		var d: Array = vb.get_item_metadata(i)
		if str(d[0]) == path:
			open_variant(int(d[1]))
		else:
			_ask_unsaved(func(): _open(str(d[0]), int(d[1]))))
	lower.add_child(vb)
	set_meta("variant_browser", vb)
	_parts = Tree.new()
	_parts.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_parts.custom_minimum_size.y = 80
	_parts.hide_root = true
	_parts.columns = 1
	_parts.focus_mode = Control.FOCUS_NONE
	_parts.add_theme_font_size_override("font_size", 14)
	_parts.tooltip_text = ""   # (each row its own tooltip - none for the list as a whole)
	_parts.set_meta("tip_fn", _parts.get_tooltip)   # (PinTips: the row's under the mouse)
	_parts.select_mode = Tree.SELECT_MULTI
	_parts.multi_selected.connect(func(it: TreeItem, _c, on: bool):
		if _syncing:
			return
		if on and it.get_metadata(0) is MeshInstance3D:
			_tree_active = it.get_metadata(0)
		if not _tree_due:
			_tree_due = true
			_sync_tree_selection.call_deferred())
	_parts.button_clicked.connect(func(it: TreeItem, _c, _id, _mb):
		var n: Node3D = it.get_metadata(0)
		n.visible = not n.visible
		_place_ghosts()
		_fill_parts()
		view.request())
	# (an overview: parts - groups of solids - with theirs under them; right-click: its menu; double-click: rename)
	_parts.allow_rmb_select = true
	_parts.item_mouse_selected.connect(func(pos: Vector2, mb: int): curve_tools.parts_click(pos, mb, _parts))
	_parts.item_edited.connect(func(): curve_tools.parts_renamed(_parts))
	_parts.visible = false   # (collections and solids: in the overview now - this list kept for its state)
	lower.add_child(_parts)
	return split


## The ECurve conversion's progress, at the foot of the left panel (outside the view): a bar and what's
## being made - shown only while solids are being converted (or a dropped object read).
func update_convert_bar() -> void:
	var ct = curve_tools
	var st: Dictionary = ct.convert_progress() if ct else {}
	var reading := has_meta("drop_job")
	var box: Control = get_meta("convert_bar") if has_meta("convert_bar") and is_instance_valid(get_meta("convert_bar")) else null
	if st.is_empty() and not reading:
		if box and box.visible:
			box.visible = false
		return
	if box == null:
		if _parts == null or _parts.get_parent() == null:
			return
		box = VBoxContainer.new()
		box.name = "ConvertProgress"
		box.add_theme_constant_override("separation", 2)
		var l := UI.label("", 14, UI.TEXT_DIM)
		l.name = "What"
		l.clip_text = true
		box.add_child(l)
		var l2 := UI.label("", 14)
		l2.name = "Stage"
		l2.clip_text = true
		box.add_child(l2)
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.custom_minimum_size.y = 14
		bar.show_percentage = false
		box.add_child(bar)
		box.tooltip_text = EditorIcons.tip("Making ECurve solids", "", "The model's solids being made ECurve solids - their edges traced, a mesh of quads made\nbetween them - in the background: keep working meanwhile.")
		_parts.get_parent().add_child(box)
		set_meta("convert_bar", box)
	box.visible = true
	var lab: Label = box.get_node("What")
	var lab2: Label = box.get_node("Stage")
	var pb: ProgressBar = box.get_node("Bar")
	if reading and st.is_empty():
		lab.text = "Reading %s..." % str(get_meta("drop_job")[2]).get_file()
		lab2.text = ""
		pb.value = 0.05
		return
	lab.text = "Making ECurve solids: %d of %d" % [int(st["index"]) + 1, int(st["total"])]
	lab2.text = "%s - %s" % [st["name"], st["stage"]]
	pb.value = (float(st["index"]) + float(st["frac"])) / maxf(1.0, float(st["total"]))


## The variant browser filled for the ECurve object at `res_path`: its original and its variants.
func fill_variant_browser(res_path := "") -> void:
	var vb: ItemList = get_meta("variant_browser") if has_meta("variant_browser") else null
	if vb == null or not is_instance_valid(vb):
		return
	if res_path == "":
		res_path = path
	vb.clear()
	if res_path == "":
		return
	var vs: Array = [] if EditTarget.is_mod() else ModelOverride.variants(res_path)
	vb.add_item("%s - original" % res_path.get_file().get_basename())
	vb.set_item_metadata(0, [res_path, 0])
	for n in vs:
		var t := ModelOverride.saved_at(res_path, n)
		vb.add_item("Variant %d%s" % [n, "  · active" if n == vs[-1] else ""])
		vb.set_item_metadata(vb.item_count - 1, [res_path, n])
		vb.set_item_tooltip(vb.item_count - 1, ("Saved %s" % Time.get_datetime_string_from_unix_time(t, true)) if t > 0 else "Not saved yet")
	if res_path == path:
		for i in vb.item_count:
			if int(vb.get_item_metadata(i)[1]) == variant:
				vb.select(i)


## A model dragged from the list: {"ecurve_model": its path} (dropped in the view: added to the open one).
func _drag_model(at: Vector2) -> Variant:
	var i := _files.get_item_at_position(at, true)
	if i < 0:
		return null
	var pth := str(_files.get_item_metadata(i))
	var l := Label.new()
	l.text = pth.get_file().get_basename()
	_files.set_drag_preview(l)
	return {"ecurve_model": pth}


## Preview in game: the model, as it is now, set down in the game under Talos to look at - not saved.
func _preview_button() -> Button:
	var b := _small("Preview in game", EditorIcons.tip("Preview in game", "", "The model as it is now (unsaved edits too) set down in front of you in the game - Talos\nhidden, the game running: walk or fly round it. F8 or Esc: back here. Only a look: nothing\nis added to the game or its save. (Talos opened from the title: your latest save loaded first,\nTalos carried over it as it is - your model, its undo history, everything.)"), preview_in_game)
	b.name = "PreviewInGame"
	b.icon = EditorIcons.get_icon("play")
	b.text = ""   # (an icon only - its tooltip says what it does)
	return b


func _wire_button() -> Button:
	var b := _small("Wireframe", EditorIcons.tip("Wireframe", "Shift+W", "The solids' edges drawn over them (in object mode too): every quad as a quad (its two triangles'\nshared edge left out), every lone triangle as one - to see the mesh's shape and spot a stretched\nor folded patch at a glance. Edges behind a surface stay hidden."), toggle_wire)
	b.name = "Wireframe"
	b.toggle_mode = true
	b.button_pressed = wire_on()
	b.icon = EditorIcons.get_icon("m_cv_wire")
	b.text = ""   # (an icon only)
	return b


## The Wireframe button beside Preview in game - put in when missing (a toolbar built before it was
## added, by a live update: there at once, no restart).
func _ensure_wire_button() -> void:
	var pv := find_child("PreviewInGame", true, false)
	if pv == null:
		return
	set_meta("wire_btn_ok", true)
	(pv as Button).text = ""   # (icons only, a live update too)
	var wb := find_child("Wireframe", true, false)
	if wb != null:
		(wb as Button).text = ""
		(wb as Button).icon = EditorIcons.get_icon("m_cv_wire")
		return
	var b := _wire_button()
	pv.get_parent().add_child(b)
	pv.get_parent().move_child(b, pv.get_index() + 1)


## The wireframe over the parts on (a meta - hot reload safe).
func wire_on() -> bool:
	return bool(get_meta("wire_on", false))


func toggle_wire() -> void:
	set_meta("wire_on", not wire_on())
	var b = find_child("Wireframe", true, false)
	if b is Button:
		(b as Button).set_pressed_no_signal(wire_on())
	set_meta("wire_sig", 0)
	update_wire()
	_say("Wireframe " + ("on" if wire_on() else "off") + ".")


## (each frame, cheap) The wireframe drawn again when a part, its mesh or its place changed.
func update_wire() -> void:
	var mi: MeshInstance3D = get_meta("wire_mi") if has_meta("wire_mi") and is_instance_valid(get_meta("wire_mi")) else null
	if not wire_on() or model == null or view == null:
		if mi:
			mi.visible = false
		return
	var sig := 0
	var ps := parts()
	for p: MeshInstance3D in ps:
		if p.is_visible_in_tree() and p.mesh:
			sig = hash([sig, p.get_instance_id(), p.mesh.get_instance_id(), p.global_transform])
	if mi and sig == int(get_meta("wire_sig", 0)):
		mi.visible = true
		return
	if curve_tools and curve_tools.active() and mi:
		mi.visible = false   # (a drag reshaping the mesh: drawn again once it's let go - ~100 ms a rebuild on a big mesh)
		return
	set_meta("wire_sig", sig)
	if mi == null:
		mi = view._overlay(Color(0.55, 0.85, 1.0, 0.55), 0.004, false, 1)
		mi.name = "PartsWire"
		set_meta("wire_mi", mi)
	var pts := PackedVector3Array()
	var idx := PackedInt32Array()
	for p: MeshInstance3D in ps:
		if not p.is_visible_in_tree() or p.mesh == null:
			continue
		var xf := p.global_transform
		for si in p.mesh.get_surface_count():
			if p.mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var a := p.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(vs.size()))
			# (points welded by place - a shaded mesh splits them at its sharp edges)
			var weld := {}
			var wid := PackedInt32Array()
			wid.resize(vs.size())
			for i in vs.size():
				var k := Vector3i((vs[i] * 1e5).round())
				if not weld.has(k):
					weld[k] = pts.size()
					pts.append(xf * vs[i])
				wid[i] = weld[k]
			var edges := {}   # "a,b" -> [triangles with it]
			var tri_n := []
			var tri_long := []
			for t in range(0, ix.size(), 3):
				var tr := [wid[ix[t]], wid[ix[t + 1]], wid[ix[t + 2]]]
				var n := (pts[tr[2]] - pts[tr[0]]).cross(pts[tr[1]] - pts[tr[0]])
				tri_n.append(n.normalized() if n.length() > 1e-14 else Vector3.ZERO)
				var lk := ""
				var ll := -1.0
				for j in 3:
					var x: int = tr[j]
					var y: int = tr[(j + 1) % 3]
					var ek := "%d,%d" % [mini(x, y), maxi(x, y)]
					if not edges.has(ek):
						edges[ek] = []
					edges[ek].append(t / 3)
					var l := pts[x].distance_to(pts[y])
					if l > ll:
						ll = l
						lk = ek
				tri_long.append(lk)
			for ek in edges:
				var ts: Array = edges[ek]
				# (a quad's diagonal - the longest edge of both its flat-together triangles: not drawn)
				if ts.size() == 2 and tri_long[ts[0]] == ek and tri_long[ts[1]] == ek and (tri_n[ts[0]] as Vector3).dot(tri_n[ts[1]]) > 0.85:
					continue
				var ab: PackedStringArray = (ek as String).split(",")
				idx.append(int(ab[0]))
				idx.append(int(ab[1]))
	view._lines(mi.mesh as ArrayMesh, pts, idx)
	mi.visible = true


func preview_in_game() -> Node:
	if model == null:
		return null
	var MP: GDScript = load("res://scripts/editor/mesh/model_preview.gd")
	var p: Node = MP.start(self)
	var scene := get_tree().current_scene
	if p == null and SaveGame.talos_overlay() == null and scene != null and not scene.has_method("get_save_data") and (scene == self or scene.is_ancestor_of(self)):
		MP.launch(self)   # (Talos from the title: into your latest save first, the model carried along)
		_say("Preview in game: loading your game...")
	elif p == null:
		_say("Preview in game: there's no game world here to preview in.")
	return p


func _build_toolbar(mid: VBoxContainer) -> void:
	var row := HFlowContainer.new()   # (one bar of icons; it wraps in a narrow window)
	row.add_theme_constant_override("h_separation", 2)
	row.add_theme_constant_override("v_separation", 2)
	mid.add_child(row)
	_toolbar = row
	_left_btn = _panel_toggle("m_panel_left", "Left panel", "Ctrl+[", "Shows or hides the left panel (the models, the shapes, the solids).", func(): set_left_panel(not left_shown))
	_mode_btn = _small("Object mode", EditorIcons.tip("Object / Edit mode", "Tab", "Object mode: whole solids - select, move, rotate, scale, add, delete.\nEdit mode: the selected solid's vertices, edges and faces."), toggle_edit)
	row.add_child(_mode_btn)
	row.add_child(_compact(_auto_select_button()))   # (Auto first: the default way to pick)
	for i in 3:
		var b := _small(KINDS[i], EditorIcons.tip(KINDS[i] + " select", str(i + 1), "Edit mode: pick %s (click, Shift+click to add, drag a box)." % ["vertices", "edges", "faces"][i]), set_kind.bind(i), true)
		_kind_btns.append(b)
		row.add_child(b)
	row.add_child(_compact(_knife_button()))
	row.add_child(_compact(_ngons_button()))
	row.add_child(VSeparator.new())
	row.add_child(_small("Front", EditorIcons.tip("Front view", "Numpad 1", "Looks at the model from the front (Ctrl: the back)."), func(): view.set_view("front")))
	row.add_child(_small("Side", EditorIcons.tip("Side view", "Numpad 3", "From the right side (Ctrl: the left)."), func(): view.set_view("side")))
	row.add_child(_small("Top", EditorIcons.tip("Top view", "Numpad 7", "From above (Ctrl: below)."), func(): view.set_view("top")))
	row.add_child(_small("Ortho", EditorIcons.tip("Perspective / orthographic", "Numpad 5", "Switches between perspective and a flat (orthographic) view."), func(): view.ortho = not view.ortho; view.update_camera()))
	_tpose_btn = _small("T-pose", EditorIcons.tip("T-pose", "Ctrl+T", "A character laid out for editing: its arms straight out to the sides, its weapon beside it.\nEdits made so are put back in its own pose when saved (animations play as before)."), toggle_tpose, true)
	row.add_child(_tpose_btn)
	_weapons_btn = _small("Weapons", EditorIcons.tip("Weapons", "Ctrl+W", "Shows or hides the model's weapons (its rifle, bow, axe... - solids of weapon materials).\nHidden, they're still there and still saved."), func(): set_weapons(not weapons_shown), true)
	_weapons_btn.button_pressed = true
	row.add_child(_weapons_btn)
	for mm in [["smart", "m_move_smart", "Smart axis move", "A drag on the selection moves it along the one of its own axes the drag goes most -\nalong its surface, across it, or out along its normal (a solid: its own axes)."],
			["perspective", "m_move_persp", "Perspective move", "A drag on the selection moves it freely over the plane you're looking at most squarely -\nthe ground from above or below, the upright one facing you from the front or side - snapping\nto one of that plane's axes while the drag runs along it."]]:
		var mb := Button.new()
		mb.toggle_mode = true
		mb.focus_mode = Control.FOCUS_NONE
		mb.icon = EditorIcons.get_icon(mm[1])
		mb.tooltip_text = EditorIcons.tip(mm[2], "", mm[3])
		mb.button_pressed = mm[0] == move_mode
		var which: String = mm[0]
		mb.pressed.connect(func(): set_move_mode(which))
		IconAnim.attach(mb, mm[1])
		_move_btns[which] = mb
		row.add_child(_compact(mb))
	_gizmo_btn = Button.new()
	_gizmo_btn.toggle_mode = true
	_gizmo_btn.focus_mode = Control.FOCUS_NONE
	_gizmo_btn.icon = EditorIcons.get_icon("m_gizmo")
	_gizmo_btn.tooltip_text = EditorIcons.tip("Gizmo", "Ctrl+G", "Shows or hides the move / turn / scale handles on the selection (arrows move along an axis,\nrings turn about one, boxes scale along one). G, R and S work either way.")
	_gizmo_btn.toggled.connect(func(_on): toggle_gizmo())
	IconAnim.attach(_gizmo_btn, "m_gizmo")
	row.add_child(_compact(_gizmo_btn))
	row.add_child(_small("Frame", EditorIcons.tip("Frame selected", "F / Numpad .", "Centres the view on the selection (Home: the whole model)."), frame_selected))
	row.add_child(_preview_button())
	row.add_child(_wire_button())
	var row2 := row
	row2.add_child(VSeparator.new())
	_prop_btn = Button.new()
	_prop_btn.toggle_mode = true
	_prop_btn.icon = EditorIcons.get_icon("m_prop")
	IconAnim.attach(_prop_btn, "m_prop")
	_compact(_prop_btn)
	_prop_btn.focus_mode = Control.FOCUS_NONE
	_prop_btn.tooltip_text = EditorIcons.tip("Proportional editing", "O", "Moving points drags their neighbours along, less the further they are - within the radius\n(the circle; the mouse wheel while moving changes it), by the falloff curve.")
	_prop_btn.toggled.connect(func(on): prop_on = on; view.request())
	row2.add_child(_prop_btn)
	_falloff = OptionButton.new()
	for f in EditMesh.FALLOFFS:
		_falloff.add_item(f.capitalize())
	_falloff.focus_mode = Control.FOCUS_NONE
	_falloff.add_theme_font_size_override("font_size", 14)
	_falloff.tooltip_text = EditorIcons.tip("Falloff", "Shift+O", "How the pull fades with distance: smooth, sphere, root, linear, sharp or constant.")
	_falloff.item_selected.connect(func(i): prop_falloff = EditMesh.FALLOFFS[i])
	row2.add_child(_falloff)
	_radius = SpinBox.new()
	_radius.min_value = 0.001
	_radius.max_value = 100.0
	_radius.step = 0.001
	_radius.value = prop_radius
	_radius.custom_minimum_size.x = 70
	_radius.tooltip_text = EditorIcons.tip("Proportional radius", "wheel while moving", "How far the pull reaches (metres, in the solid's own scale).")
	_radius.value_changed.connect(func(v): prop_radius = v)
	row2.add_child(_radius)
	_connected = Button.new()
	_connected.toggle_mode = true
	_connected.icon = EditorIcons.get_icon("m_connected")
	IconAnim.attach(_connected, "m_connected")
	_compact(_connected)
	_connected.focus_mode = Control.FOCUS_NONE
	_connected.tooltip_text = EditorIcons.tip("Connected only", "Alt+O", "Only points joined to the selection by edges are pulled (distance measured along the edges) -\nan arm doesn't drag the body next to it.")
	_connected.toggled.connect(func(on): prop_connected = on)
	row2.add_child(_connected)
	row2.add_child(VSeparator.new())
	for a in 3:
		var b := _small("XYZ"[a], EditorIcons.tip("Symmetry " + "XYZ"[a], "", "Edits mirror across the %s axis: what you do to a point is done to its twin on the other side." % "XYZ"[a]), func(): sym[a] = not sym[a], true)
		_sym_btns.append(b)
		row2.add_child(b)
	row2.add_child(_small("Symmetrize", EditorIcons.tip("Symmetrize", "", "Copies the side you've changed onto the other (Shift+click: +X onto -X); the axis is the first\nsymmetry axis turned on (X if none). Each point's twin is the one it matched before your edits."), func(): symmetrize(_sym_axis(), true, not Input.is_key_pressed(KEY_SHIFT))))
	row2.add_child(_small("Symmetrize topology", EditorIcons.tip("Symmetrize topology", "Ctrl+Shift+M", "Rebuilds the other side as the mirror of the side you've changed - its faces, cuts and points,\nnot just its positions: cut at the mirror plane, the other side deleted, the changed side mirrored\nonto it and welded along the seam (Shift+click: the other way). A character's copied side\nfollows its own bones (.L / .R)."), func(): symmetrize_topology(_sym_axis(), true, not Input.is_key_pressed(KEY_SHIFT))))


func _build_right() -> Control:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size.x = 220
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	sc.add_child(box)
	box.add_child(EditorIcons.tipped(UI.section("SOLID"), EditorIcons.tip("Solid", "", "The selected solid: its name, where it is (place, turn, size), the primitives to add, and binding\nit to a character's skeleton.")))
	var name_e := LineEdit.new()
	name_e.add_theme_font_size_override("font_size", 14)
	name_e.placeholder_text = "(no solid selected)"
	name_e.tooltip_text = EditorIcons.tip("Rename", "Enter", "The selected solid's name (kept in the saved file).")
	name_e.text_submitted.connect(func(t): rename_part(t); name_e.release_focus())
	name_e.focus_exited.connect(func():
		if part and name_e.text != str(part.name):
			rename_part(name_e.text))
	_fields["name"] = name_e
	box.add_child(name_e)
	var grid := GridContainer.new()
	grid.columns = 4
	box.add_child(grid)
	for f in [["position", "Position", -1000.0, 1000.0, 0.01, "m_move"], ["rotation", "Rotation", -360.0, 360.0, 0.5, "m_rotate"], ["scale", "Scale", -100.0, 100.0, 0.01, "m_scale"]]:
		var ic := TextureRect.new()   # (its icon for its name: the row's tooltip says it)
		ic.texture = EditorIcons.get_icon(f[5])
		ic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		ic.tooltip_text = EditorIcons.tip(f[1], "", "The solid's %s on X, Y and Z." % f[1].to_lower())
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		grid.add_child(ic)
		var spins := []
		for a in 3:
			var s := SpinBox.new()
			s.min_value = f[2]
			s.max_value = f[3]
			s.step = f[4]
			s.allow_greater = true
			s.allow_lesser = true
			s.custom_minimum_size.x = 56
			s.tooltip_text = EditorIcons.tip("%s %s" % [f[1], "XYZ"[a]], "G / R / S", "The solid's %s on the %s axis%s." % [f[1].to_lower(), "XYZ"[a], " (degrees)" if f[0] == "rotation" else ""])
			s.value_changed.connect(func(_v): _field_changed(f[0]))
			spins.append(s)
			grid.add_child(s)
		_fields[f[0]] = spins
	var prims := HFlowContainer.new()
	prims.add_theme_constant_override("h_separation", 2)
	prims.add_theme_constant_override("v_separation", 2)
	for k in MeshIO.PRIMITIVES:
		prims.add_child(_small(k.capitalize(), EditorIcons.tip("Add " + k, "Shift+A", "Adds a %s (a metre across) as a new solid, at the model's origin." % k), add_primitive.bind(k)))
	box.add_child(prims)
	var ops := prims   # (with the primitives: one row of icons)
	ops.add_child(_btn("Duplicate", "duplicate", "Shift+D", "A copy of the selected solid (beside it in the solids list).", duplicate_part))
	ops.add_child(_btn("Delete solid", "delete", "X / Delete", "Removes the selected solid.", delete_part))
	_build_bind(box)
	shape_tools.build_right(box)

	box.add_child(EditorIcons.tipped(UI.section("MIRROR MODIFIER"), EditorIcons.tip("Mirror modifier", "", "The selected solid mirrored across its own X / Y / Z: you shape one side, the other follows\n(applied when saved).")))
	var mrow := HBoxContainer.new()
	for a in 3:
		var c := CheckBox.new()
		c.text = "XYZ"[a]
		c.focus_mode = Control.FOCUS_NONE
		c.add_theme_font_size_override("font_size", 14)
		c.tooltip_text = EditorIcons.tip("Mirror across " + "XYZ"[a], "", "The solid shows a mirrored copy across its own %s axis - live while you edit; it's applied into\nthe mesh when you save (or with Apply)." % "XYZ"[a])
		c.toggled.connect(func(_on): _mirror_changed())
		_mirror["axis%d" % a] = c
		mrow.add_child(c)
	var clip := CheckBox.new()
	clip.text = "Clip"
	clip.focus_mode = Control.FOCUS_NONE
	clip.add_theme_font_size_override("font_size", 14)
	clip.tooltip_text = EditorIcons.tip("Clip at the seam", "", "Points can't cross the mirror's plane; points on it stay on it.")
	clip.button_pressed = true
	clip.toggled.connect(func(_on): _mirror_changed())
	_mirror["clip"] = clip
	mrow.add_child(clip)
	box.add_child(mrow)
	var mrow2 := mrow
	mrow2.add_child(UI.label("Merge", 14, UI.TEXT_DIM))
	var merge := SpinBox.new()
	merge.min_value = 0.0
	merge.max_value = 1.0
	merge.step = 0.0001
	merge.value = 0.001
	merge.custom_minimum_size.x = 70
	merge.tooltip_text = EditorIcons.tip("Merge distance", "", "Points this close to the mirror's plane are joined with their twins when it's applied (no seam).")
	merge.value_changed.connect(func(_v): _mirror_changed())
	_mirror["merge"] = merge
	mrow2.add_child(merge)
	mrow2.add_child(_small("Apply", EditorIcons.tip("Apply the mirror", "", "Makes the mirrored copy part of the mesh, and removes the modifier."), apply_mirror))

	_edit_box = VBoxContainer.new()
	_edit_box.add_child(EditorIcons.tipped(UI.section("EDIT MESH"), EditorIcons.tip("Edit mesh", "Tab", "Edit mode's operations on the selected vertices, edges and faces.")))
	# The selection's coordinates (its one point, or the middle of several - in the part's own
	# space), live as it's moved; typed, the selection moves there.
	var sr := HBoxContainer.new()
	sr.add_theme_constant_override("separation", 2)
	_sel_count = UI.label("", 14, UI.TEXT_DIM)
	_sel_count.custom_minimum_size.x = 30
	_sel_count.tooltip_text = EditorIcons.tip("Selection", "", "How many points are selected; the numbers beside: where they are - one point's own place,\nor the middle of several - in the solid's own space (metres).")
	_sel_count.mouse_filter = Control.MOUSE_FILTER_STOP
	sr.add_child(_sel_count)
	for a in 3:
		var sp := SpinBox.new()
		sp.min_value = -1000.0
		sp.max_value = 1000.0
		sp.step = 0.001
		sp.allow_greater = true
		sp.allow_lesser = true
		sp.custom_minimum_size.x = 56
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.tooltip_text = EditorIcons.tip("Selection %s" % "XYZ"[a], "", "Where the selection is on %s (its one point, or the middle of several), live as it moves.\nType a value to move it there (proportional editing and symmetry apply)." % "XYZ"[a])
		sp.value_changed.connect(func(v): _sel_coord_typed(a, v))
		_sel_spins.append(sp)
		sr.add_child(sp)
	_edit_box.add_child(sr)
	var eg := HFlowContainer.new()
	eg.add_theme_constant_override("h_separation", 2)
	eg.add_theme_constant_override("v_separation", 2)
	for o in [["Extrude", "E", "The selected faces pulled out along their normal, with walls round them - then move them."],
			["Delete", "X / Delete", "Vertex mode: the faces touching the selected points; edge: those along the edges; face: the faces."],
			["Merge", "M", "The selected points made one, at their centre."],
			["Subdivide", "", "The selected faces cut in four (their neighbours split to match)."],
			["Dissolve", "Ctrl+X", "Points: the faces round each made one, the point gone. Edges: the faces either side made one.\nFaces: those side by side made one, the points inside them gone. (Auto: whatever's picked.)"],
			["Flip normals", "", "The selected faces (all, if none) turned to face the other way."],
			["Recalc normals", "", "The shading worked out again from the faces (hard edges kept)."],
			["Select all", "A", "Everything (Alt+A: nothing)."],
			["Spherize", "Shift+Alt+S", "The selected points pushed onto a sphere round their middle - the mouse sets how far\n(further from the middle: rounder), or type 1-9 (10-90%) or 0 (100%); click to keep it."],
			["Curve deform", "V", "A curve laid along the selection, end to end: drag its two ends and two handles in the view\nand the points follow it, bent as it bends (X / Y / Z: drag along an axis). Enter keeps it."],
			["Flatten", "Shift+Alt+F", "The selected points pressed onto a plane through their middle - the one that fits them best\n(the selected faces' plane), or X / Y / Z: the solid's axis plane. The mouse sets how far, or\ntype 1-9 (10-90%) or 0 (100%); click to keep it."],
			["Material island", "L", "From the selected faces, every face joined to them that has the same material - up to\nwhere another material starts (a face under the mouse with nothing selected: from it)."]]:
		eg.add_child(_small(o[0], EditorIcons.tip(o[0], o[1], o[2]), _edit_action.bind(o[0])))
	_edit_box.add_child(eg)
	mesh_ops.build_panel(_edit_box)
	box.add_child(_edit_box)

	box.add_child(EditorIcons.tipped(UI.section("MATERIAL"), EditorIcons.tip("Material", "", "The selected solid's materials: colour, metal, roughness, glow - from the library or its own.")))
	var surf := OptionButton.new()
	surf.add_theme_font_size_override("font_size", 14)
	surf.focus_mode = Control.FOCUS_NONE
	surf.tooltip_text = EditorIcons.tip("Surface", "", "The solid's surfaces - each has a material of its own: picked here, it shows below to edit\n(a change shows on every surface that uses the material).")
	surf.item_selected.connect(func(_i): _show_material())
	_mat["surface"] = surf
	box.add_child(surf)
	mat_tools.build_right(box)
	ref_images.build_right(box)
	box.move_child(_edit_box, 0)   # (edit mesh first: what's used most)
	# Two tabs: the mesh's tools, and Curve modeling (curves sketched on a plane, made into solids) -
	# each its own page, so neither gets crowded.
	_right_tabs = TabContainer.new()
	_right_tabs.custom_minimum_size.x = 220
	_right_tabs.add_theme_font_size_override("font_size", 14)
	sc.name = "Mesh"
	_right_tabs.add_child(sc)
	var csc := ScrollContainer.new()
	csc.name = "Curve modeling"
	csc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var cbox := VBoxContainer.new()
	cbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cbox.add_theme_constant_override("separation", 1)
	csc.add_child(cbox)
	curve_tools.build_panel(cbox)
	_right_tabs.add_child(csc)
	_right_tabs.set_tab_tooltip(0, "The solid, edit mesh, booleans, shapes, mirror, materials, reference images.")
	_right_tabs.set_tab_tooltip(1, "Curve modeling: lines, splines, circles, arcs, rectangles and polygons drawn on a construction\nplane (snapped to its grid and to points), then extruded, revolved, lofted, swept or piped into solids.\nWith this tab open: L line, P spline, C circle, Shift+C arc, Shift+R rectangle, Shift+P polygon, E extrude.")
	_right_tabs.tab_changed.connect(func(_t): curve_tools._refresh_panel())
	merge_side_panel()
	return _right_tabs


## (the panel is one page now) The side panel shown.
func show_right_tab(_i: int) -> void:
	if not right_shown:
		set_right_panel(true)


## Curve modeling's keys and clicks work: in object mode (edit mode's keys are the mesh's).
func curve_tab_shown() -> bool:
	return mode == "object"


## The side panel's sections in order: the mesh's and Curve modeling's on one page (no tabs), each shown
## only when it's about what's selected (update_side_panel).
const SIDE_ORDER := ["EDIT MESH", "OVERVIEW", "SOLID", "RECIPE", "EDGES", "SKETCH", "SOLIDS FROM EDGES", "BOOLEAN", "SHAPE",
	"MIRROR MODIFIER", "MATERIAL", "REFERENCE IMAGES"]


## The two tabs' pages made one: every section (its heading and what's under it, up to the next heading)
## gathered into a box of its own, in SIDE_ORDER, on the first page; the second page gone, the tab bar
## hidden. (Run on a panel built as tabs - at build, or live on one built before.)
func merge_side_panel() -> void:
	if _right_tabs == null or _right_tabs.get_tab_count() < 2:
		return
	var secs := {}
	var loose := []
	for pi in 2:
		var box: Node = _right_tabs.get_child(pi).get_child(0)
		var cur: VBoxContainer = null
		for c in box.get_children():
			var t := _section_title(c)
			if t != "":
				if c is VBoxContainer and c.get_child_count() > 0 and _section_title(c.get_child(0)) != "":
					secs[t] = c   # (a box of its own already: EDIT MESH, SOLID)
					box.remove_child(c)
					cur = null
					continue
				cur = VBoxContainer.new()
				cur.name = "Sec_" + t.validate_node_name()
				cur.add_theme_constant_override("separation", 3)
				secs[t] = cur
			box.remove_child(c)
			if cur:
				cur.add_child(c)
			else:
				loose.append(c)
	var page: ScrollContainer = _right_tabs.get_child(0)
	var main: VBoxContainer = page.get_child(0)
	for c in loose:
		main.add_child(c)
	for t in SIDE_ORDER:
		if secs.has(t):
			main.add_child(secs[t])
			secs.erase(t)
	for t in secs:
		main.add_child(secs[t])
	var second := _right_tabs.get_child(1)
	_right_tabs.remove_child(second)
	second.queue_free()
	page.name = "Panel"
	_right_tabs.tabs_visible = false
	set_meta("side_secs", _side_sections())
	update_side_panel()


## A section heading's text ("" - not one): a heading label, or a box that starts with one.
func _section_title(c: Node) -> String:
	var l: Node = c
	if c is VBoxContainer and c.get_child_count() > 0:
		l = c.get_child(0)
	if l is Label and str((l as Label).text) in SIDE_ORDER + ["ON THE MESH", "PART", "CURVES", "SOLIDS FROM CURVES"]:
		return str((l as Label).text)
	return ""


func _side_sections() -> Dictionary:
	var out := {}
	if _right_tabs == null or _right_tabs.get_child_count() == 0:
		return out
	for c in _right_tabs.get_child(0).get_child(0).get_children():
		var t := _section_title(c)
		if t != "":
			out[t] = c
	return out


## Only what's about the selection shown: edit mode - the mesh's editing; a part - its place, shape, mirror
## and material (two: the booleans); curves, points, a patch or a whole baked solid picked - Curve
## modeling's (sketch settings while drawing or with curves picked; nothing picked: the overview, the
## sketch settings and the reference images).
func update_side_panel() -> void:
	var secs: Dictionary = get_meta("side_secs", {})
	if secs.is_empty():
		return
	var ct = curve_tools
	var has_part := part != null and is_instance_valid(part)
	var curve_pick: bool = ct != null and (not ct.sel.is_empty() or not ct.picked_points().is_empty() or not ct.picked_patch().is_empty() or ct.picked_solid() != null)
	var drawing: bool = ct != null and ct.tool != ""
	var nothing := not has_part and not curve_pick
	var on := {
		"EDIT MESH": false,   # (no mesh editing: ECurve objects are edited by their solids, faces, edges and vertices)
		"OVERVIEW": model != null,
		"SOLID": has_part,
		"RECIPE": has_part and mode == "object",
		"EDGES": curve_pick,
		"SKETCH": drawing or nothing or (ct != null and not ct.sel.is_empty()) or (ct != null and not ct.picked_points().is_empty()),
		"SOLIDS FROM EDGES": ct != null and not ct.sel.is_empty() and ct.picked_patch().is_empty() and ct.picked_solid() == null,
		"BOOLEAN": mode == "object" and selected_parts().size() >= 2,
		"SHAPE": has_part and mode == "object" and part.has_meta("mesh_shape"),
		"MIRROR MODIFIER": has_part,
		"MATERIAL": has_part,
		"REFERENCE IMAGES": nothing,
		"ON THE MESH": false,
	}
	for t in secs:
		var c = secs[t]
		if is_instance_valid(c):
			var want: bool = on.get(t, true)
			if t == "RECIPE":
				want = want and not (ct.part_spec() as Dictionary).is_empty()   # (its own box: a solid made from edges)
			(c as Control).visible = want


# --- the model -----------------------------------------------------------------

## An empty model (`quiet`: at start - nothing to ask, nothing changed).
func new_model(quiet := false) -> void:
	var root := Node3D.new()
	root.name = "Model"
	_set_model(root, "")
	if not quiet:
		_say("A new, empty model: add solids from the panel on the right.")


## Opens the model at `res_path` (the mod's copy, in a mod) - read on a worker thread.
func open(res_path: String) -> void:
	_ask_unsaved(func(): _open(res_path))


func _open(res_path: String, v := -1) -> void:
	if _task >= 0:
		return
	_pending_variant = _variant_to_open(res_path, v)
	var file := _model_source(res_path, _pending_variant)
	loading = true
	_say("Opening %s..." % res_path)
	_task_out = []
	_task_kind = "open:" + res_path
	_task = WorkerThreadPool.add_task(func(): _task_out = [MeshIO.read(file)], false, "ECurves editor: open")


## The same, on this thread (tests, and the Mod Editor when it must have it now).
func open_now(res_path: String, v := -1) -> bool:
	_pending_variant = _variant_to_open(res_path, v)
	var n := MeshIO.read(_model_source(res_path, _pending_variant))
	if n == null:
		_say("Couldn't read %s." % res_path)
		return false
	set_meta("open_now", true)   # (opened here and now - tests, the Mod Editor: as it is; opening it from the list converts it)
	_set_model(n, res_path)
	remove_meta("open_now")
	return true


func _set_model(root: Node3D, res_path: String) -> void:
	variant = _pending_variant
	_pending_variant = 0
	_refresh_variants(res_path)
	if mode == "edit":
		_leave_edit(false)
	_cancel_xf()
	if model:
		for p in _ghosts:
			for g in _ghosts[p]:
				g.queue_free()
		_ghosts.clear()
		model.queue_free()
	_drop_entries(_undo + _redo)
	_undo.clear()
	_redo.clear()
	model = root
	path = res_path
	ref_images.model_opened(res_path)
	curve_tools.model_opened(res_path)
	part = null
	sel_parts = []
	_menu_prev = null
	_outlined_more = []
	for p in model.find_children("*", "MeshInstance3D", true, false):   # (parts made from shapes: their recipes back)
		var ex = p.get_meta("extras", {})
		if ex is Dictionary and ex.get("atrapos_shape") is Dictionary:
			p.set_meta("mesh_shape", ex["atrapos_shape"])
		if ex is Dictionary and ex.get("atrapos_curves") is Dictionary:
			p.set_meta("curve_solid", ex["atrapos_curves"])
			_ecurve_skin(p as MeshInstance3D)
	view.world.add_child(model)
	for sk in model.find_children("*", "Skeleton3D", true, false):
		(sk as Skeleton3D).reset_bone_poses()   # (the rest pose: as the mesh is stored)
	for ap in model.find_children("*", "AnimationPlayer", true, false):
		(ap as AnimationPlayer).stop()
	_model_mats = []
	for p in parts():
		var m: Mesh = p.mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			if mat and not mat in _model_mats:
				_model_mats.append(mat)
		if p.has_meta("mesh_mirror"):
			_make_ghosts(p)
	dirty = false
	mat_tools.model_changed()
	_fill_parts()
	frame_all()
	if not has_meta("open_now"):
		# (an ECurve object: any solid that isn't one yet made one, in the background - then it's stored so)
		curve_tools.convert_parts(parts(), {"kind": "open", "path": res_path} if res_path != "" else {})
	var ps := parts()
	if not ps.is_empty():
		select_part(ps[0])
	_update_ui()
	if res_path != "":
		var nv := 0
		for p in ps:
			for i in p.mesh.get_surface_count():
				nv += p.mesh.surface_get_array_len(i)
		_say("%s: %d solids, %d vertices." % [res_path, ps.size(), nv])


## The model's parts: its MeshInstance3Ds, in tree order.
func parts() -> Array:
	if model == null:
		return []
	var out := []
	for n in model.find_children("*", "MeshInstance3D", true, false):
		if n.has_meta("weapons_of"):
			continue   # (a model's weapons, hidden: TPose / set_weapons)
		if (n as MeshInstance3D).mesh != null:
			out.append(n)
	return out


func _fill_parts() -> void:
	_syncing = true
	_parts.clear()
	var root := _parts.create_item()
	var eye := EditorIcons.get_icon("eye")
	var eye_off := EditorIcons.get_icon("eye_off")
	# parts (groups of solids, curve_tools.is_group) as rows with what's in them under them
	var rows := {}
	if model:
		for g in curve_tools.groups():
			var up: Node = curve_tools.group_of(g)
			var gi := _parts.create_item(rows.get(up, root))
			gi.set_text(0, str(g.name))
			gi.set_metadata(0, g)
			gi.set_editable(0, true)
			gi.set_tooltip_text(0, "A solid: a group of solids. Click: select them all. Right-click: more; double-click: rename.")
			gi.add_button(0, eye if g.visible else eye_off, 0, false, "Hide / show")
			rows[g] = gi
	for p: MeshInstance3D in parts():
		var g: Node = curve_tools.group_of(p)
		var it := _parts.create_item(rows.get(g, root))
		var depth := 0
		var n := p.get_parent()
		while n and n != model and n != g:
			depth += 1
			n = n.get_parent()
		it.set_text(0, "  ".repeat(depth) + str(p.name) + ("  (mirror)" if p.has_meta("mesh_mirror") else "") + ("  (bound)" if p.has_meta("bound_part") else ""))
		it.set_metadata(0, p)
		it.set_editable(0, true)
		it.set_tooltip_text(0, "%s - %s. Click: select (Ctrl+click: more, two for a boolean); double-click: rename;\nright-click: more." % [p.name, "a solid made from curves" if p.has_meta("curve_solid") else "a mesh"])
		it.add_button(0, eye if p.visible else eye_off, 0, false, "Hide / show")
		if p == part or p in sel_parts:
			it.select(0)
	_syncing = false


## Selects part `p` (null: none); `add`: Ctrl / Shift - added to the selection (or taken out
## of it, if it's in) - the multi-selection a boolean works on.
func select_part(p: MeshInstance3D, add := false) -> void:
	if mode == "edit" and p != part:
		_leave_edit(true)
	_menu_prev = null
	var kept: Array = selected_parts().filter(func(q): return curve_tools and curve_tools.locked(q))   # (not selectable: stays as it is)
	if p and curve_tools and curve_tools.locked(p) and not p in kept:
		return
	if add and p:
		sel_parts = selected_parts()
		if p in sel_parts and sel_parts.size() > 1 and not p in kept:
			sel_parts.erase(p)
			p = sel_parts.back()
		elif not p in sel_parts:
			sel_parts.append(p)
	else:
		sel_parts = ([p] if p else []) + kept.filter(func(q): return q != p)
	part = p
	_selected_now()


## Parts `ps` all selected at once (a collection picked: its solids) - the panels filled once, not once a
## part (ninety solids were ninety overview refills, over a second); the last of them the current part.
func select_parts(ps: Array) -> void:
	var on := ps.filter(func(q): return q != null and not (curve_tools and curve_tools.locked(q)))
	if on.is_empty():
		select_part(null)
		return
	if mode == "edit" and on.back() != part:
		_leave_edit(true)
	_menu_prev = null
	var kept: Array = selected_parts().filter(func(q): return curve_tools and curve_tools.locked(q))
	var seen := {}
	sel_parts = []
	for q in on + kept:
		if not seen.has(q):
			seen[q] = true
			sel_parts.append(q)
	part = on.back()
	_selected_now()


## The selection just set (sel_parts, part): the parts list, panels and view brought up to it.
func _selected_now() -> void:
	var inset := {}
	for q in sel_parts:
		inset[q] = true
	_syncing = true
	_parts.deselect_all()
	for it in (_parts.get_root().get_children() if _parts.get_root() else []):
		if inset.has(it.get_metadata(0)):
			it.select(0)
	_syncing = false
	_show_part()
	_show_material_list()
	_update_ui()
	view.request()


func _show_part() -> void:
	_syncing = true
	var on := part != null
	(_fields["name"] as LineEdit).text = str(part.name) if on else ""
	(_fields["name"] as LineEdit).editable = on
	for f in ["position", "rotation", "scale"]:
		var v := Vector3.ZERO
		if on:
			v = part.position if f == "position" else (part.rotation_degrees if f == "rotation" else part.scale)
		for a in 3:
			var s: SpinBox = _fields[f][a]
			s.editable = on
			s.set_value_no_signal(v[a])
	var mm: Dictionary = part.get_meta("mesh_mirror", {}) if on else {}
	for a in 3:
		(_mirror["axis%d" % a] as CheckBox).set_pressed_no_signal(bool(mm.get("axes", [false, false, false])[a]))
	(_mirror["clip"] as CheckBox).set_pressed_no_signal(bool(mm.get("clip", true)))
	(_mirror["merge"] as SpinBox).set_value_no_signal(float(mm.get("merge", 0.001)))
	_fill_bones()
	_syncing = false


func _field_changed(f: String) -> void:
	if _syncing or part == null:
		return
	var v := Vector3(_fields[f][0].value, _fields[f][1].value, _fields[f][2].value)
	var p := part
	var before := p.transform
	match f:
		"position": p.position = v
		"rotation": p.rotation_degrees = v
		"scale": p.scale = v
	var after := p.transform
	_push("Set " + f, func(): p.transform = before; _transformed(), func(): p.transform = after; _transformed())
	_transformed()


func _transformed() -> void:
	_place_ghosts()
	if not _syncing:
		_show_part()
	if em:
		_overlays()
	view.request()


func rename_part(t: String) -> void:
	t = t.strip_edges().validate_node_name()
	if part == null or t == "" or t == str(part.name):
		return
	var p := part
	var old := str(p.name)
	_do("Rename", func(): p.name = t; _fill_parts(); _show_part(), func(): p.name = old; _fill_parts(); _show_part())


func add_primitive(kind: String) -> MeshInstance3D:
	if mode == "edit":
		_leave_edit(true)
	if model == null:
		new_model(true)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshIO.primitive(kind)
	mi.mesh.surface_set_material(0, MeshIO.default_material())
	mi.name = _unique(kind.capitalize())
	var m := model
	var add := func():
		m.add_child(mi)
		mi.owner = m
		_bind_new(mi)
		_fill_parts()
		select_part(mi)
	var remove := func():
		m.remove_child(mi)
		if part == mi:
			part = null
		_fill_parts()
		_show_part()
		_update_ui()
		view.request()
	_do("Add " + kind, add, remove, [mi])
	return mi


func duplicate_part() -> void:
	if part == null:
		return
	if mode == "edit":
		_leave_edit(true)
	var src := part
	var d: MeshInstance3D = src.duplicate()
	d.mesh = src.mesh.duplicate()
	d.name = _unique(str(src.name))
	var parent := src.get_parent()
	var add := func():
		parent.add_child(d)
		parent.move_child(d, src.get_index() + 1)
		d.owner = model
		_bind_new(d)
		if d.has_meta("mesh_mirror"):
			_make_ghosts(d)
		_fill_parts()
		select_part(d)
	var remove := func():
		_free_ghosts(d)
		parent.remove_child(d)
		_fill_parts()
		select_part(src)
	_do("Duplicate", add, remove, [d])


func delete_part() -> void:
	if part == null:
		return
	if mode == "edit":
		_leave_edit(true)
	var p := part
	var parent := p.get_parent()
	var at := p.get_index()
	var remove := func():
		_free_ghosts(p)
		parent.remove_child(p)
		part = null
		_fill_parts()
		_show_part()
		_show_material_list()
		_update_ui()
		view.request()
	var add := func():
		parent.add_child(p)
		parent.move_child(p, at)
		p.owner = model
		if p.has_meta("mesh_mirror"):
			_make_ghosts(p)
		_fill_parts()
		select_part(p)
	_do("Delete solid", remove, add, [p])


func _unique(base: String) -> String:
	var names := {}
	for p in parts():
		names[str(p.name)] = true
	if not names.has(base):
		return base
	var i := 2
	while names.has("%s%d" % [base, i]):
		i += 1
	return "%s%d" % [base, i]


# --- the mirror modifier --------------------------------------------------------

func _mirror_changed() -> void:
	if _syncing or part == null:
		return
	var axes := [(_mirror["axis0"] as CheckBox).button_pressed, (_mirror["axis1"] as CheckBox).button_pressed, (_mirror["axis2"] as CheckBox).button_pressed]
	var mm := {"axes": axes, "clip": (_mirror["clip"] as CheckBox).button_pressed, "merge": (_mirror["merge"] as SpinBox).value}
	set_mirror(part, mm if axes.has(true) else {})


## The part's mirror modifier ({axes: [x, y, z], clip, merge}; {}: none).
func set_mirror(p: MeshInstance3D, mm: Dictionary) -> void:
	var old: Dictionary = p.get_meta("mesh_mirror", {})
	var put := func(d: Dictionary):
		if d.is_empty():
			p.remove_meta("mesh_mirror")
		else:
			p.set_meta("mesh_mirror", d.duplicate(true))
		_make_ghosts(p)
		_fill_parts()
		if p == part:
			_show_part()
		view.request()
	_do("Mirror modifier", put.bind(mm), put.bind(old))


## The mirrored copies shown for a part with a mirror modifier: instances
## of its own mesh, reflected (one for each axis and each pair of axes...).
func _make_ghosts(p: MeshInstance3D) -> void:
	_free_ghosts(p)
	var mm: Dictionary = p.get_meta("mesh_mirror", {})
	if mm.is_empty():
		return
	var axes: Array = mm["axes"]
	var list := []
	for combo in range(1, 8):
		var ok := true
		for a in 3:
			if combo & (1 << a) and not axes[a]:
				ok = false
		if not ok:
			continue
		var g := MeshInstance3D.new()
		g.name = "MirrorGhost"
		g.mesh = p.mesh
		g.set_meta("combo", combo)
		view.sv.add_child(g)
		list.append(g)
	_ghosts[p] = list
	_place_ghosts()


func _free_ghosts(p: MeshInstance3D) -> void:
	for g in _ghosts.get(p, []):
		g.queue_free()
	_ghosts.erase(p)


func _place_ghosts() -> void:
	for p: MeshInstance3D in _ghosts:
		if not is_instance_valid(p):
			continue
		for g: MeshInstance3D in _ghosts[p]:
			var c: int = g.get_meta("combo")
			var s := Vector3(-1 if c & 1 else 1, -1 if c & 2 else 1, -1 if c & 4 else 1)
			g.mesh = p.mesh
			g.visible = p.is_inside_tree() and p.is_visible_in_tree()
			if p.is_inside_tree():
				g.global_transform = p.global_transform * Transform3D(Basis.from_scale(s), Vector3.ZERO)


## The mesh of `p` with its mirror modifier applied.
func mirrored_mesh(p: MeshInstance3D) -> Mesh:
	var mm: Dictionary = p.get_meta("mesh_mirror", {})
	if mm.is_empty():
		return p.mesh
	var e = EditMesh.from_mesh(p.mesh)
	e.apply_mirror(mm["axes"], float(mm.get("merge", 0.001)), bool(mm.get("clip", true)))
	return e.to_mesh()


## Applies the selected part's mirror into its mesh (the modifier goes).
func apply_mirror() -> void:
	if part == null or not part.has_meta("mesh_mirror"):
		_say("The solid has no mirror modifier.")
		return
	if mode == "edit":
		_leave_edit(true)
	var p := part
	var before: Mesh = p.mesh
	var mm: Dictionary = p.get_meta("mesh_mirror")
	var after := mirrored_mesh(p)
	var put := func(m: Mesh, d: Dictionary):
		p.mesh = m
		if d.is_empty():
			p.remove_meta("mesh_mirror")
		else:
			p.set_meta("mesh_mirror", d)
		_make_ghosts(p)
		_fill_parts()
		_show_part()
		view.request()
	_do("Apply mirror", put.bind(after, {}), put.bind(before, mm))


# --- edit mode -----------------------------------------------------------------

func toggle_edit() -> void:
	if mode == "edit":
		_leave_edit(true)
	else:
		enter_edit()


## Edit mode on the selected part (`now`: prepared on this thread whatever its size).
func enter_edit(now := false) -> void:
	if part == null or part.mesh == null or _task >= 0:
		_update_ui()
		return
	var nv := 0
	for i in part.mesh.get_surface_count():
		nv += part.mesh.surface_get_array_len(i)
	var m: Mesh = part.mesh
	if now or nv <= BIG:
		_edit_ready(EditMesh.from_mesh(m))
		return
	loading = true
	_say("Preparing %s for editing (%d vertices)..." % [part.name, nv])
	_task_out = []
	_task_kind = "edit"
	_task_part = part
	_task = WorkerThreadPool.add_task(func(): _task_out = [EditMesh.from_mesh(m)], false, "ECurves editor: edit mode")


func _edit_ready(e) -> void:
	em = e
	_ref_key = ""
	_sym_ref()   # (the points as edit mode begins: the sides' pairing)
	mode = "edit"
	_part_mesh_before = part.mesh
	em.update_mesh()
	part.mesh = em.mesh
	_em_tm = null
	_eundo.clear()
	_eredo.clear()
	sel_p = PackedByteArray(); sel_p.resize(em.points.size())
	sel_e = PackedByteArray(); sel_e.resize(em.edge_count())
	sel_t = PackedByteArray(); sel_t.resize(em.tri_count())
	sel_pa = PackedByteArray(); sel_pa.resize(em.points.size())   # (Auto's own points: Auto is the default)
	_place_ghosts()
	_overlays()
	_update_ui()
	_say("Editing %s: %d points, %d faces. 1 / 2 / 3: vertices, edges, faces; Tab: back to the solids." % [part.name, em.points.size(), em.poly_count()])


## Back to object mode; the edits become one step of the model's undo.
func _leave_edit(keep := true) -> void:
	if em == null:
		mode = "object"
		return
	_cancel_xf()
	knife_cancel()
	_wait_tm()
	var p := part
	var before := _part_mesh_before
	if em.unused:   # (points dissolved: the vertices nothing uses dropped from the mesh kept)
		em.compact()
		em.update_mesh()
	var after: Mesh = em.mesh
	if not keep:
		p.mesh = before
	elif not _eundo.is_empty():
		# (its vertices edited: a part made from a shape is a plain mesh from now on)
		# (and one made from curves stops following them)
		var shp: Dictionary = p.get_meta("mesh_shape", {})
		var cso: Dictionary = p.get_meta("curve_solid", {})
		p.remove_meta("mesh_shape")
		p.remove_meta("curve_solid")
		if not cso.is_empty():
			_say("%s's mesh edited: a plain mesh now - its curves no longer change it (undo: linked again)." % p.name)
		_push("Edit " + str(p.name), func():
			p.mesh = before
			if not shp.is_empty():
				p.set_meta("mesh_shape", shp)
			if not cso.is_empty():
				p.set_meta("curve_solid", cso)
			_place_ghosts(); _update_ui(); view.request(), func():
			p.mesh = after
			p.remove_meta("mesh_shape")
			p.remove_meta("curve_solid")
			_place_ghosts(); _update_ui(); view.request())
	em = null
	_em_tm = null
	_eundo.clear()
	_eredo.clear()
	mode = "object"
	view.show_overlays(null, Transform3D(), 0, sel_p, sel_e, sel_t)
	_place_ghosts()
	_update_ui()
	_say("Object mode.")


func set_kind(k: int) -> void:
	if k == 3 and sel_kind != 3 and em:
		# (into Auto: the points picked so far kept as points, edges and faces as they are)
		sel_pa = sel_p.duplicate() if sel_kind == 0 else PackedByteArray()
		sel_pa.resize(em.points.size())
	sel_kind = k
	if em:
		_derive_sel()
		_overlays()
	_update_ui()


## The selection's other two forms from the one being edited.
func _derive_sel() -> void:
	_material_follows_selection.call_deferred()
	_sel_version += 1
	var nt: int = em.tri_count()
	var ne: int = em.edge_count()
	if sel_kind == 3:
		# Auto: points, edges and faces each picked as they are; the points moved are all of theirs
		sel_pa.resize(em.points.size())
		em.close_to_polys(sel_t)
		sel_p = sel_pa.duplicate()
		for e in mini(ne, sel_e.size()):
			if sel_e[e]:
				sel_p[em.edges[e * 2]] = 1
				sel_p[em.edges[e * 2 + 1]] = 1
		for t in mini(nt, sel_t.size()):
			if sel_t[t]:
				for k in 3:
					sel_p[em.tris[t * 3 + k]] = 1
		return
	if sel_kind == 1:
		sel_p.fill(0)
		for e in ne:
			if sel_e[e]:
				sel_p[em.edges[e * 2]] = 1
				sel_p[em.edges[e * 2 + 1]] = 1
	elif sel_kind == 2:
		sel_p.fill(0)
		for t in nt:
			if sel_t[t]:
				for k in 3:
					sel_p[em.tris[t * 3 + k]] = 1
	if sel_kind != 1:
		for e in ne:
			sel_e[e] = 1 if sel_p[em.edges[e * 2]] and sel_p[em.edges[e * 2 + 1]] else 0
		if sel_kind == 2:
			# (in face mode an edge is selected only if a selected face has it)
			sel_e.fill(0)
			for t in nt:
				if sel_t[t]:
					for k in 3:
						var ed: int = em.edge(em.tris[t * 3 + k], em.tris[t * 3 + (k + 1) % 3])
						if ed >= 0:
							sel_e[ed] = 1
	if sel_kind != 2:
		for t in nt:
			sel_t[t] = 1 if sel_p[em.tris[t * 3]] and sel_p[em.tris[t * 3 + 1]] and sel_p[em.tris[t * 3 + 2]] else 0
		em.close_to_polys(sel_t)   # (a face selected whole or not at all)


func _resize_sel() -> void:
	sel_pa.resize(em.points.size())
	sel_p.resize(em.points.size())
	sel_e.resize(em.edge_count())
	sel_t.resize(em.tri_count())


## The selected points (ids).
func selected_points() -> PackedInt32Array:
	var out := PackedInt32Array()
	if em == null:
		return out
	for p in sel_p.size():
		if sel_p[p]:
			out.append(p)
	return out


## Selects points `ids` (and what they make up), replacing the selection unless `add`.
func select_points(ids: PackedInt32Array, add := false) -> void:
	if not add:
		sel_p.fill(0)
		sel_e.fill(0)
		sel_t.fill(0)
	for p in ids:
		sel_p[p] = 1
	var keep := sel_kind
	sel_kind = 0
	_derive_sel()
	sel_kind = keep
	if keep == 3:
		sel_pa = sel_p.duplicate()
		sel_e.fill(0)
		sel_t.fill(0)
	_overlays()


var _hovering := false   # (an overlay refresh for the hover only: the whole wireframe kept)


func _overlays() -> void:
	_sync_gizmo()
	_sync_sel_coords(true)
	if em == null or part == null:
		return
	view.show_overlays(em, part.global_transform, sel_kind, sel_p, sel_e, sel_t, _focus, _focus_r, _focus_seeds, not _hovering)
	if not _hovering:
		show_stats()


## Records an edit-mode change (before: em.snapshot() taken before it).
func _edit_done(name: String, before: Dictionary) -> void:
	_sel_version += 1
	_edit_count += 1
	_sym_ref()   # (points added or removed - extrude, delete, subdivide: paired again as they are now)
	before["sel"] = [before.get("sel_p", sel_p), before.get("sel_e", sel_e), before.get("sel_t", sel_t), before.get("sel_pa", sel_pa)]
	var after: Dictionary = em.snapshot()
	after["sel"] = [sel_p.duplicate(), sel_e.duplicate(), sel_t.duplicate(), sel_pa.duplicate()]
	_eundo.append({"name": name, "undo": _restore.bind(before), "redo": _restore.bind(after)})
	# (each step holds two copies of the mesh: a big one keeps fewer steps - ~200 MB at most)
	var cap := clampi(int(UNDO_BYTES / maxf(1.0, 2.0 * em.snapshot_bytes())), 8, UNDO_MAX)
	while _eundo.size() > cap:
		_eundo.pop_front()
	_eredo.clear()
	dirty = true
	_mesh_changed()


func _restore(snap: Dictionary) -> void:
	em.restore(snap)
	var s: Array = snap["sel"]
	sel_p = s[0].duplicate()
	sel_e = s[1].duplicate()
	sel_t = s[2].duplicate()
	sel_pa = s[3].duplicate() if s.size() > 3 else sel_p.duplicate()
	_resize_sel()
	_mesh_changed()


func _mesh_changed() -> void:
	em.update_mesh()
	_start_tm()
	_overlays()


# The picking mesh (a TriangleMesh of the edit mesh) is made again on a worker after each
# edit; the next pick waits for it (by then it's usually done).
var _tm_task := -1
var _tm_out: Array = []


func _start_tm() -> void:
	_wait_tm()
	_em_tm = null
	var pts: PackedVector3Array = em.points.duplicate()
	var tr: PackedInt32Array = em.tris   # (never changed in place)
	var out: Array = []
	_tm_out = out
	_tm_task = WorkerThreadPool.add_task(func(): out.append(EditMesh.make_triangle_mesh(pts, tr)), false, "ECurves editor: picking")


func _wait_tm() -> void:
	if _tm_task < 0:
		return
	WorkerThreadPool.wait_for_task_completion(_tm_task)
	_tm_task = -1
	if not _tm_out.is_empty():
		_em_tm = _tm_out[0]
	_tm_out = []


## An edit-mode operation: Extrude, Delete, Merge, Subdivide, Flip normals,
## Recalc normals, Select all.
func _edit_action(what: String) -> void:
	if em == null:
		enter_edit(true)
		if em == null:
			return
	match what:
		"Extrude": extrude()
		"Delete": delete_selected()
		"Merge": merge_selected()
		"Subdivide": subdivide()
		"Dissolve": dissolve_selected()
		"Flip normals": flip_normals()
		"Recalc normals": recalc_normals()
		"Select all": select_all(true)
		"Material island": select_material_island()
		"Spherize": spherize()
		"Curve deform": deform.begin_curve()
		"Flatten": deform.begin_flatten()


## Select island by material: from each selected face (none selected: the faces round the selected
## points, else the face under the mouse), every face reached across shared edges whose surface has
## the same material - stopping where another material starts. Adds to the selection.
## Spherize (Shift+Alt+S): the selected points pushed onto a sphere round their middle - as big as
## they are from it on average - by a strength from 0 (as they were) to 1 (a sphere): the mouse's
## distance from the middle (twice as far as it began: all the way), or a digit typed (1-9: 10-90%,
## 0: 100%). Click keeps it, right-click / Esc cancels; proportional editing and symmetry apply.
func spherize() -> void:
	if mode != "edit" or em == null:
		_say("Spherize works on points: Tab into edit mode and select some.")
		return
	if selected_points().size() < 3:
		_say("Spherize needs at least three points selected.")
		return
	begin_transform("SPH")


func _spherize_step(m0: Vector2, m: Vector2, ps: Vector2) -> void:
	var f: float = xf["sph_f"]
	if f < 0.0:
		f = clampf((m - ps).length() / maxf(1.0, (m0 - ps).length()) - 1.0, 0.0, 1.0)
	var c: Vector3 = xf["sph_c"]
	var r: float = xf["sph_r"]
	var ids: PackedInt32Array = xf["ids"]
	var orig: PackedVector3Array = xf["orig"]
	var w: PackedFloat32Array = xf["w"]
	for k in ids.size():
		var o := orig[k]
		var d := o - c
		var on := c + d.normalized() * r if d.length() > 1e-7 else o
		em.points[ids[k]] = o.lerp(on, f * w[k])
	view.hint = "Spherize  %d%%   (mouse: further out - rounder · 1-9: 10-90%%, 0: 100%% · click: done · right-click / Esc: cancel)" % roundi(f * 100.0)


func select_material_island() -> int:
	if em == null or part == null:
		return 0
	var nt: int = em.tri_count()
	var seeds := PackedInt32Array()
	for t in mini(nt, sel_t.size()):
		if sel_t[t]:
			seeds.append(t)
	if seeds.is_empty():
		for t in nt:
			for k in 3:
				if sel_p[em.tris[t * 3 + k]]:
					seeds.append(t)
					break
	if seeds.is_empty():
		var t := _pick_tri(_mouse)
		if t >= 0:
			seeds.append(t)
	if seeds.is_empty():
		_say("Select a face (or point at one) first.")
		return 0
	var mat_of := func(t: int) -> Variant:
		var sf: int = em.tri_surf[t]
		return part.mesh.surface_get_material(sf) if sf < part.mesh.get_surface_count() else sf
	var seen := PackedByteArray()
	seen.resize(nt)
	var stack: Array = []
	for t in seeds:
		seen[t] = 1
		stack.append(t)
	var n := 0
	while not stack.is_empty():
		var t: int = stack.pop_back()
		n += 1
		var m = mat_of.call(t)
		for k in 3:
			var e: int = em.tri_edges[t * 3 + k]
			if e < 0:
				continue
			var across := [em.edge_tris[e * 2], em.edge_tris[e * 2 + 1]]
			if em.edge_more.has(e):
				across.append_array(Array(em.edge_more[e]))
			for o in across:
				if o < 0 or o >= nt or seen[o]:
					continue
				if mat_of.call(o) != m:
					continue   # (another material: the island's edge)
				seen[o] = 1
				stack.append(o)
	for t in nt:
		if seen[t]:
			sel_t[t] = 1
	if sel_kind == 0 or sel_kind == 1:
		set_kind(2)   # (faces picked: shown as faces)
	_derive_sel()
	_overlays()
	_say("Material island: %d triangles of the same material selected." % n)
	return n


func _snap() -> Dictionary:
	var s: Dictionary = em.snapshot()
	s["sel_p"] = sel_p.duplicate()
	s["sel_e"] = sel_e.duplicate()
	s["sel_t"] = sel_t.duplicate()
	s["sel_pa"] = sel_pa.duplicate()
	return s


## The faces the selection makes up (face mode: those picked).
func _sel_tris() -> PackedByteArray:
	return sel_t.duplicate()


func select_all(on: bool) -> void:
	if em == null:
		return
	sel_p.fill(1 if on else 0)
	sel_e.fill(1 if on else 0)
	sel_t.fill(1 if on else 0)
	sel_pa.resize(sel_p.size())
	sel_pa.fill(1 if on else 0)
	_overlays()


func extrude(then_move := true) -> PackedInt32Array:
	var ts := _sel_tris()
	if not ts.has(1):
		_say("Extrude: select faces first (3: face mode).")
		return PackedInt32Array()
	var before := _snap()
	# their average normal (local): the way the new faces go
	var n := Vector3.ZERO
	for t in ts.size():
		if ts[t]:
			var a: Vector3 = em.points[em.tris[t * 3]]
			var b: Vector3 = em.points[em.tris[t * 3 + 1]]
			var c: Vector3 = em.points[em.tris[t * 3 + 2]]
			n += (a - c).cross(a - b)
	var top: PackedInt32Array = em.extrude(ts)
	_resize_sel()
	var flag := PackedByteArray()
	flag.resize(em.points.size())
	for p in top:
		flag[p] = 1
	sel_p.fill(0)
	sel_e.fill(0)
	sel_t.fill(0)
	for p in top:
		sel_p[p] = 1
	for t in em.tri_count():
		sel_t[t] = 1 if flag[em.tris[t * 3]] and flag[em.tris[t * 3 + 1]] and flag[em.tris[t * 3 + 2]] else 0
	var keep := sel_kind
	sel_kind = 2
	_derive_sel()
	sel_kind = keep
	if keep != 2:
		sel_kind = 0
		_derive_sel()
		sel_kind = keep
	if keep == 3:   # (Auto: the new faces picked)
		sel_pa.fill(0)
		sel_e.fill(0)
		_derive_sel()
	_edit_done("Extrude", before)
	if then_move and n.length() > 1e-9:
		begin_transform("G", (part.global_basis * n).normalized())
	return top


func delete_selected() -> void:
	var ts := PackedByteArray()
	ts.resize(em.tri_count())
	for t in em.tri_count():
		var a: int = em.tris[t * 3]; var b: int = em.tris[t * 3 + 1]; var c: int = em.tris[t * 3 + 2]
		match sel_kind:
			0: ts[t] = 1 if sel_p[a] or sel_p[b] or sel_p[c] else 0
			1:
				var ab: int = em.edge(a, b); var bc: int = em.edge(b, c); var ca: int = em.edge(c, a)
				ts[t] = 1 if (ab >= 0 and sel_e[ab]) or (bc >= 0 and sel_e[bc]) or (ca >= 0 and sel_e[ca]) else 0
			2: ts[t] = sel_t[t]
			3:
				var ab: int = em.edge(a, b); var bc: int = em.edge(b, c); var ca: int = em.edge(c, a)
				ts[t] = 1 if sel_t[t] or sel_pa[a] or sel_pa[b] or sel_pa[c] or (ab >= 0 and sel_e[ab]) or (bc >= 0 and sel_e[bc]) or (ca >= 0 and sel_e[ca]) else 0
	ts = em.grow_to_polys(ts)   # (a face goes whole)
	if not ts.has(1):
		_say("Nothing selected to delete.")
		return
	var before := _snap()
	em.delete_tris(ts)
	_resize_sel()
	select_all(false)
	_edit_done("Delete", before)


func merge_selected() -> void:
	var ids := selected_points()
	if ids.size() < 2:
		_say("Merge: select two points or more.")
		return
	var before := _snap()
	var p: int = em.merge(ids)
	_resize_sel()
	select_all(false)
	if p >= 0:
		sel_p[p] = 1
		if sel_kind == 3:
			sel_pa[p] = 1
		set_kind(sel_kind)
	_edit_done("Merge", before)


func subdivide() -> void:
	var ts := _sel_tris()
	if not ts.has(1):
		_say("Subdivide: select faces first.")
		return
	var before := _snap()
	var pts: PackedInt32Array = em.subdivide(ts)
	_resize_sel()
	select_points(pts)
	_edit_done("Subdivide", before)


func flip_normals() -> void:
	var before := _snap()
	var ts := _sel_tris()
	em.flip(ts if ts.has(1) else PackedByteArray())
	_edit_done("Flip normals", before)


func recalc_normals() -> void:
	var before := _snap()
	em.recalc_normals()
	_edit_done("Recalc normals", before)


func _sym_axis() -> int:
	for a in 3:
		if sym[a]:
			return a
	return 0


## Copies the `positive` side of `axis` onto the other (in edit mode: the part being edited).
## Symmetrize: one side copied onto the other across `axis` - each point's twin found where
## the two sides last matched (the points as edit mode began, or as the last symmetrize left
## them: SymRef), so twins are still paired after one side's been moved. `auto`: from the
## side that's been changed since then onto the other (else `positive`: + onto -).
func symmetrize(axis := 0, positive := true, auto := false) -> void:
	if em == null:
		enter_edit(true)
		if em == null:
			return
	_sym_ref()
	var ref: PackedVector3Array = _ref_pts
	var m := _mirror_map(axis)
	var tol: float = maxf(em.aabb().size.length() * 0.0005, 0.0005)
	if auto:
		var moved := [0.0, 0.0]   # (how far each side's points moved since they matched: - side, + side)
		for i in mini(ref.size(), em.points.size()):
			if absf(ref[i][axis]) > tol:
				moved[1 if ref[i][axis] > 0.0 else 0] += (em.points[i] as Vector3).distance_to(ref[i])
		if moved[0] > 0.0 or moved[1] > 0.0:
			positive = moved[1] >= moved[0]
	var sgn := 1.0 if positive else -1.0
	var before := _snap()
	var pts: PackedVector3Array = em.points
	var changed := 0
	var unpaired := 0
	for i in mini(ref.size(), pts.size()):
		var side := ref[i][axis] * sgn
		if absf(ref[i][axis]) <= tol:
			if pts[i][axis] != 0.0:   # (on the seam: kept on it)
				pts[i][axis] = 0.0
				changed += 1
			continue
		if side < 0.0:
			continue
		var j: int = m[i]
		if j < 0 or j == i:
			unpaired += 1
			continue
		var want: Vector3 = em.mirrored(pts[i], axis)
		if not pts[j].is_equal_approx(want):
			pts[j] = want
			changed += 1
	if changed == 0:
		_say("Symmetrize: the two sides already match." + (" (%d points have no twin)" % unpaired if unpaired > 0 else ""))
		return
	em.points = pts
	em.sync()
	em.recalc_normals()
	_edit_done("Symmetrize", before)
	_ref_key = ""
	_sym_ref()   # (the sides match again: pairing from here on)
	_say("Symmetrize: %d points moved (%s%s onto the other side)%s." % [changed, "+" if positive else "-", "XYZ"[axis],
		(" - %d points have no twin" % unpaired) if unpaired > 0 else ""])


## The points as they were when the two sides last matched (edit mode began, or the last
## symmetrize, or the mesh's points were added or removed): twins are paired there.
var _ref_pts := PackedVector3Array()
var _ref_key := ""


func _sym_ref() -> void:
	var k := "%d|%d|%d" % [em.get_instance_id(), em.topo, em.points.size()]
	if k != _ref_key:
		_ref_key = k
		_ref_pts = em.points.duplicate()
		_mm.clear()
		_tri_of.clear()


# --- transforms -------------------------------------------------------------

## Starts moving (G), rotating (R) or scaling (S) the selection - the part in
## object mode, the points in edit mode - with the mouse; `axis`: a locked
## direction (world) for a move.
func begin_transform(kind: String, axis := Vector3.ZERO) -> void:
	_cancel_xf()
	var x := {"kind": kind, "axis": -1, "dir": axis, "m0": _mouse}
	if mode == "object":
		if part == null or kind in ["SPH", "CRV", "FLT"]:
			return   # (spherize: points - edit mode)
		x["orig"] = part.global_transform
		x["pivot"] = part.global_position
		# (every selected solid moves; a part - a group - whose solids are all selected moves as one)
		var nodes := xf_nodes()
		var origs := []
		var mid := Vector3.ZERO
		for n: Node3D in nodes:
			origs.append(n.global_transform)
			mid += n.global_position
		x["nodes"] = nodes
		x["origs"] = origs
		if nodes.size() > 1 or nodes[0] != part:
			x["pivot"] = mid / nodes.size()
	else:
		if em == null:
			return
		var sel := selected_points()
		if sel.is_empty():
			_say("Select something first.")
			return
		x["sel"] = sel
		x["snap"] = _snap()
		x["pivot"] = part.global_transform * em.centroid(sel)
		_xf_influence(x)
		if kind == "SPH":
			# (the sphere: round the selection's middle, as big as its points are from it on average)
			var c: Vector3 = em.centroid(sel)
			var r := 0.0
			for i in sel:
				r += (em.points[i] as Vector3).distance_to(c)
			x["sph_c"] = c
			x["sph_r"] = r / maxf(1.0, sel.size())
			x["sph_f"] = -1.0   # (by the mouse until a digit's typed)
	xf = x
	_xf_update()


## The points a transform moves: the selection, its proportional falloff, the
## symmetry twins and the clipping sides - and their vertices.
func _xf_influence(x: Dictionary) -> void:
	var r := prop_radius if prop_on else 0.0
	var inf: Array = em.influence(x["sel"], r, prop_falloff, prop_connected)
	var ids: PackedInt32Array = inf[0]
	var w: PackedFloat32Array = inf[1]
	var moving := PackedByteArray()
	moving.resize(em.points.size())
	for p in ids:
		moving[p] = 1
	# symmetry: each moved point's twin follows it (both moved: the + side leads)
	var pairs := PackedInt32Array()
	var lead := ids.duplicate()
	var driven := PackedByteArray()
	driven.resize(em.points.size())
	for a in 3:
		if not sym[a]:
			continue
		var mm: PackedInt32Array = em.mirror_map(a)
		var now := lead.duplicate()
		for p in now:
			var q := mm[p]
			if q < 0 or q == p or driven[p]:
				continue
			if moving[q] and em.points[p][a] < 0.0:
				continue   # (its twin leads)
			if not driven[q]:
				driven[q] = 1
				pairs.append_array(PackedInt32Array([p, q, a]))
				if not moving[q]:
					moving[q] = 1
					lead.append(q)
	# the twins led by others aren't moved by the transform themselves
	var ids2 := PackedInt32Array()
	var w2 := PackedFloat32Array()
	for k in ids.size():
		if not driven[ids[k]]:
			ids2.append(ids[k])
			w2.append(w[k])
	var all := ids2.duplicate()
	for i in range(0, pairs.size(), 3):
		all.append(pairs[i + 1])
	var orig := PackedVector3Array()
	for p in ids2:
		orig.append(em.points[p])
	# the mirror modifier's clipping
	var mm: Dictionary = part.get_meta("mesh_mirror", {})
	var clip_axes := [false, false, false]
	var side := PackedFloat32Array()
	if not mm.is_empty() and mm.get("clip", true):
		clip_axes = mm["axes"]
		var tol := float(mm.get("merge", 0.001))
		for p in all:
			for a in 3:
				var c: float = em.points[p][a]
				side.append(0.0 if absf(c) <= tol else signf(c))
	x["ids"] = ids2
	x["w"] = w2
	x["orig"] = orig
	x["pairs"] = pairs
	x["all"] = all
	x["clip_axes"] = clip_axes
	x["side"] = side
	x["verts"] = em.verts_of(all)


func _xf_update() -> void:
	if xf.is_empty():
		return
	if xf.has("step"):   # (a tool's own: mesh_ops' inset and loop slide)
		(xf["step"] as Callable).call()
		return
	var pivot: Vector3 = xf["pivot"]
	var m0: Vector2 = xf["m0"]
	var m := _mouse
	var t := Transform3D()
	var ax: int = xf["axis"]
	var dir: Vector3 = xf["dir"]
	var lock := Vector3.ZERO
	if ax >= 0:
		lock = Vector3.ZERO
		lock[ax] = 1.0
	elif dir != Vector3.ZERO:
		lock = dir
	var ps := view.project(pivot)
	# The locked axis drawn through what's moving (in its colour - X red, Y green, Z blue).
	if xf.has("plane"):
		pass   # (a perspective move draws its own snapped axis: _perspective_step)
	elif lock != Vector3.ZERO:
		var ln := lock.normalized()
		var col := Color(1, 1, 1, 0.9)
		if xf.has("axis_k"):
			col = MeshView.AXIS_COL[int(xf["axis_k"])]
		else:
			for k in 3:
				if absf(absf(ln[k]) - 1.0) < 0.001:
					col = MeshView.AXIS_COL[k]
		view.axis_line = {"at": pivot, "dir": ln, "col": col}
	else:
		view.axis_line = {}
	if xf.has("plane"):
		view.hint = ""
	match xf["kind"]:
		"G":
			var d: Vector3
			if xf.has("plane"):
				d = _perspective_step(pivot, m0, m)
			elif lock != Vector3.ZERO:
				d = view.on_line(m, pivot, lock) - view.on_line(m0, pivot, lock)
			else:
				d = view.on_view_plane(m, pivot) - view.on_view_plane(m0, pivot)
			t = Transform3D(Basis(), d)
			view.hint = (view.hint if xf.has("plane") else "") + "Move  %.3f, %.3f, %.3f" % [d.x, d.y, d.z]
		"R":
			var a0 := (m0 - ps).angle()
			var a1 := (m - ps).angle()
			var ang := a1 - a0
			var vz: Vector3 = view.cam.global_basis.z
			var axis := vz if lock == Vector3.ZERO else lock * (1.0 if lock.dot(vz) >= 0.0 else -1.0)
			var b := Basis(axis.normalized(), -ang)
			t = Transform3D(b, pivot - b * pivot)
			view.hint = "Rotate  %.1f°" % rad_to_deg(-ang)
		"S":
			var f := (m - ps).length() / maxf(1.0, (m0 - ps).length())
			var b := Basis.from_scale(Vector3(f, f, f))
			if lock != Vector3.ZERO:   # (an axis - typed X / Y / Z, or the gizmo's box on one: stretched along it only)
				var l := lock.normalized()
				b = Basis(Vector3.RIGHT + l * ((f - 1.0) * l.x), Vector3.UP + l * ((f - 1.0) * l.y), Vector3.BACK + l * ((f - 1.0) * l.z))
			t = Transform3D(b, pivot - b * pivot)
			view.hint = "Scale  %.3f" % f
	var dir_name := ""
	if dir != Vector3.ZERO and xf.has("axis_k"):
		dir_name = "   " + (["along its surface (X)", "across its surface (Y)", "along its normal (Z)"][int(xf["axis_k"])] if mode == "edit" else "its own " + "XYZ"[int(xf["axis_k"])])
	elif dir != Vector3.ZERO:
		dir_name = "   along the normal"
		for k in 3:
			if absf(absf(dir.normalized()[k]) - 1.0) < 0.001:
				dir_name = "   axis " + "XYZ"[k]
	view.hint += ("   axis " + "XYZ"[ax] if ax >= 0 else dir_name) + "   (X / Y / Z: lock an axis · click / Enter: done · right-click / Esc: cancel%s)" % (" · wheel: radius" if prop_on and mode == "edit" else "")
	if mode == "object":
		_set_xfs(xf, t)
		_syncing = true
		_show_part()
		_syncing = false
		_place_ghosts()
		view.request()
		return
	var g := part.global_transform
	var local := g.affine_inverse() * t * g
	if xf["kind"] == "SPH":
		_spherize_step(m0, m, ps)
	elif xf["kind"] in DeformTools.KINDS:
		deform.step(m0, m, ps)
	else:
		em.place(xf["ids"], xf["orig"], xf["w"], local)
	em.follow(xf["pairs"])
	if (xf["clip_axes"] as Array).has(true):
		em.clip(xf["all"], xf["side"], xf["clip_axes"])
	em.sync(xf["verts"])
	_refill = true
	_sync_sel_coords()
	if prop_on:
		view.circle_at = ps
		var r_world := prop_radius * g.basis.get_scale().x
		view.circle_r = (view.project(pivot + view.cam.global_basis.x * r_world) - ps).length()
	view.request()


func _process(_dt: float) -> void:
	if not has_meta("wire_btn_ok"):
		_ensure_wire_button()
	if not has_meta("tip_views3_ok") and _files != null:
		set_meta("tip_views3_ok", true)
		_tip_pics()
	if not has_meta("save_as_ok") and _header != null and _save_btn != null and _save_btn.get_parent() == _header:
		# (an editor opened before: its Save as moved next to Save)
		set_meta("save_as_ok", true)
		for b in _header.get_children():
			if b is Button and (b as Button).icon == EditorIcons.get_icon("export"):
				_header.move_child(b, _save_btn.get_index() + 1)
	if not has_meta("main_btns_ok") and _header != null:
		# (an editor opened before they left the right-click menu: their header buttons shown again)
		set_meta("main_btns_ok", true)
		hide_menu_twins()
		for b in _header.find_children("*", "Button", true, false):
			if (b as Button).icon in [EditorIcons.get_icon("undo"), EditorIcons.get_icon("redo"), EditorIcons.get_icon("save")]:
				(b as Button).visible = true
	if has_meta("drop_marker") or has_meta("drop_reads"):
		var mk = (get_meta("drop_marker") if has_meta("drop_marker") else null)
		var over: bool = view != null and view.get_global_rect().has_point(view.get_global_mouse_position())
		if not get_viewport().gui_is_dragging():
			_drop_marker_end()
		elif not over and mk != null and is_instance_valid(mk):
			(mk as Node3D).visible = false   # (dragged out of the view)
	if has_meta("drop_job"):
		_drop_step()
	if has_meta("store_gather"):
		_store_gather_step()
	if has_meta("store_job"):
		_store_step()
	if has_meta("store_write"):
		_store_write_step()
	update_convert_bar()
	if view and view.has_method("hook_cursor"):
		view.hook_cursor()   # (a view made before a live reload: given what it's missing)
	if wire_on() or has_meta("wire_mi"):
		update_wire()
	if _tpose_task >= 0 and WorkerThreadPool.is_task_completed(_tpose_task):
		WorkerThreadPool.wait_for_task_completion(_tpose_task)
		_tpose_task = -1
		if not _tpose_out.is_empty():
			_tpose_done()
	if _hover_due and Time.get_ticks_msec() - _hover_ms >= 16 and mode == "edit" and _drag == "" and xf.is_empty():
		_hover(_mouse)   # (the last move inside the throttle: shown too)
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		loading = false
		var out = _task_out[0] if not _task_out.is_empty() else null
		_task_out = []
		if _task_kind.begins_with("open:"):
			var p := _task_kind.trim_prefix("open:")
			if out is Node3D:
				_set_model(out, p)
			else:
				_say("Couldn't read %s." % p)
		elif _task_kind == "edit" and out != null and part != null and part == _task_part and mode == "object":
			_edit_ready(out)
	if _scan_task >= 0 and WorkerThreadPool.is_task_completed(_scan_task):
		WorkerThreadPool.wait_for_task_completion(_scan_task)
		_scan_task = -1
		if not _scan_out.is_empty():
			_all_files = _scan_out[0]
			_fill_files()
	if _refill and em:
		_refill = false
		em.update_mesh()
		view.move_overlays(em)


## Done: the transform stays (one undo step).
func confirm_transform() -> void:
	if view:
		view.axis_line = {}
		view.queue_redraw()
	call_deferred("_sync_gizmo")
	if xf.is_empty():
		return
	var x := xf
	xf = {}
	view.hint = ""
	view.circle_r = 0.0
	if mode == "object":
		var nodes: Array = x.get("nodes", [part])
		var before: Array = x.get("origs", [x["orig"]])
		var after := nodes.map(func(n: Node3D): return n.global_transform)
		if before != after:
			_push("Transform", _put_xfs.bind(nodes, before), _put_xfs.bind(nodes, after))
		_transformed()
		return
	_refill = false
	em.recalc_normals(x["verts"])
	mesh_ops.after_transform(x)   # (Auto merge: what it moved onto other points welded - in the same step)
	if x.has("name"):
		_edit_done(x["name"], x["snap"])
		return
	_edit_done({"G": "Move", "R": "Rotate", "S": "Scale", "SPH": "Spherize", "CRV": "Curve deform", "FLT": "Flatten"}.get(x["kind"], "Edit"), x["snap"])


## What an object-mode transform moves: the selected parts - each part (a group of solids) whose
## solids are all selected as one - and nothing whose parent moves already.
func xf_nodes() -> Array:
	var sel := selected_parts()
	var out: Array = []
	for p: Node3D in sel:
		var n: Node3D = p
		var g := curve_tools.group_of(p)
		while g and curve_tools.group_parts(g).all(func(q): return q in sel):
			n = g
			g = curve_tools.group_of(g)
		if not n in out:
			out.append(n)
	out = out.filter(func(n): return not out.any(func(o): return o != n and o.is_ancestor_of(n)))
	return out if not out.is_empty() else [part]


func _set_xfs(x: Dictionary, t: Transform3D) -> void:
	var nodes: Array = x.get("nodes", [part])
	var origs: Array = x.get("origs", [x["orig"]])
	for i in nodes.size():
		if is_instance_valid(nodes[i]):
			(nodes[i] as Node3D).global_transform = t * (origs[i] as Transform3D)


func _put_xfs(nodes: Array, xfs: Array) -> void:
	for i in nodes.size():
		if is_instance_valid(nodes[i]):
			(nodes[i] as Node3D).global_transform = xfs[i]
	_transformed()


func _cancel_xf() -> void:
	if view:
		view.axis_line = {}
		view.queue_redraw()
	if xf.is_empty():
		return
	var x := xf
	xf = {}
	view.hint = ""
	view.circle_r = 0.0
	if mode == "object":
		if part:
			_put_xfs(x.get("nodes", [part]), x.get("origs", [x["orig"]]))
		return
	if x.has("on_cancel"):   # (a tool's own: an inset undone, a loop slide kept in the middle)
		(x["on_cancel"] as Callable).call(x)
		return
	if em:
		_refill = false
		em.restore(x["snap"])
		_mesh_changed()


## Edit-mode move by `d` (local units) of the selection, as G would (with
## proportional editing, symmetry and clipping) - for tests and typed moves.
func move_selection(d: Vector3) -> void:
	if em == null:
		return
	var x := {"kind": "G", "axis": -1, "dir": Vector3.ZERO, "m0": _mouse}
	x["sel"] = selected_points()
	if (x["sel"] as PackedInt32Array).is_empty():
		return
	x["snap"] = _snap()
	x["pivot"] = part.global_transform * em.centroid(x["sel"])
	_xf_influence(x)
	em.place(x["ids"], x["orig"], x["w"], Transform3D(Basis(), d))
	em.follow(x["pairs"])
	if (x["clip_axes"] as Array).has(true):
		em.clip(x["all"], x["side"], x["clip_axes"])
	em.sync(x["verts"])
	xf = x
	confirm_transform()


# --- picking ---------------------------------------------------------------------

func _pick_part(at: Vector2) -> MeshInstance3D:
	var r := view.ray(at)
	var best: MeshInstance3D = null
	var bd := INF
	for p: MeshInstance3D in parts():
		if not p.is_visible_in_tree() or (curve_tools and curve_tools.locked(p)):
			continue   # (hidden, or not selectable: clicks go through it)
		var tm: TriangleMesh = p.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var inv := p.global_transform.affine_inverse()
		var hit := tm.intersect_ray(inv * (r[0] as Vector3), (inv.basis * (r[1] as Vector3)).normalized())
		if hit.is_empty():
			continue
		var d: float = (p.global_transform * (hit["position"] as Vector3)).distance_to(r[0])
		if d < bd:
			bd = d
			best = p
			_pick_face = int(hit.get("face_index", -1))
	return best


var _pick_face := -1   # (the last _pick_part's triangle, in the part's mesh)


## What the wheel zooms towards: the model's surface under the mouse, else the point under it at the
## depth of the view's centre.
func _zoom_point(at: Vector2) -> Vector3:
	var r := view.ray(at)
	var best := INF
	var hit_at := Vector3.INF
	for p: MeshInstance3D in parts():
		if not p.is_visible_in_tree() or p.mesh == null:
			continue
		var tm: TriangleMesh = p.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var inv := p.global_transform.affine_inverse()
		var hit := tm.intersect_ray(inv * (r[0] as Vector3), (inv.basis * (r[1] as Vector3)).normalized())
		if hit.is_empty():
			continue
		var w: Vector3 = p.global_transform * (hit["position"] as Vector3)
		var d := w.distance_to(r[0])
		if d < best:
			best = d
			hit_at = w
	if hit_at != Vector3.INF:
		return hit_at
	return view.on_view_plane(at, view.target)


## The surface of `p`'s mesh that triangle `face` (in surface order) is in (-1: none).
func _surface_of_face(p: MeshInstance3D, face: int) -> int:
	if p == null or p.mesh == null or face < 0:
		return -1
	var n := 0
	for i in p.mesh.get_surface_count():
		var ix: int = p.mesh.surface_get_array_index_len(i)
		n += (ix if ix > 0 else p.mesh.surface_get_array_len(i)) / 3
		if face < n:
			return i
	return -1


## The MATERIAL panel on surface `s` of the selected part (the list and the panel), if it isn't already.
func _show_surface(s: int, note := "") -> void:
	if part == null or s < 0 or s >= part.mesh.get_surface_count():
		return
	var surf: OptionButton = _mat["surface"]
	if surf.item_count != part.mesh.get_surface_count():
		_show_material_list()
	if surf.selected != s:
		surf.select(s)
		_show_material()
	if note != "":
		_say(note)


## Edit mode: the panel follows the selection - the surface (and material) most of the selected faces
## are on; several: that one, and how many others.
func _material_follows_selection() -> void:
	if em == null or part == null or mode != "edit":
		return
	var count := {}
	for t in mini(sel_t.size(), em.tri_count()):
		if sel_t[t]:
			var sf: int = em.tri_surf[t]
			count[sf] = int(count.get(sf, 0)) + 1
	if count.is_empty():
		return
	var best := -1
	for sf in count:
		if best < 0 or count[sf] > count[best]:
			best = sf
	var m: Material = part.mesh.surface_get_material(best) if best < part.mesh.get_surface_count() else null
	_show_surface(best, ("The selected faces use %d materials - showing %s (most of them)." % [count.size(), m.resource_name if m else "surface %d" % (best + 1)]) if count.size() > 1 else "")


## The triangle under the mouse (-1: none).
## Edit mode: the area under the mouse at `at` shows its wireframe and points (a circle
## of HOVER_PX on screen, as big on the model as that is where the mouse touches it).
func _hover(at: Vector2) -> void:
	if em == null or part == null:
		return
	var now := Time.get_ticks_msec()
	if now - _hover_ms < 16:
		_hover_due = true
		return
	_hover_ms = now
	_hover_due = false
	var t := _pick_tri(at)
	_auto_preview(at if t >= 0 else Vector2(-1, -1))
	if t < 0:
		if _focus != Vector3.INF:
			_focus = Vector3.INF
			_focus_seeds = PackedInt32Array()
			_hovering = true
			_overlays()
			_hovering = false
		return
	_focus = _last_hit
	_focus_seeds = PackedInt32Array([em.tris[t * 3], em.tris[t * 3 + 1], em.tris[t * 3 + 2]])
	var g := part.global_transform * _focus
	var px_world := 0.0
	if view.cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		px_world = view.cam.size / maxf(view.size.y, 1.0)
	else:
		px_world = 2.0 * view.cam.global_position.distance_to(g) * tan(deg_to_rad(view.cam.fov * 0.5)) / maxf(view.size.y, 1.0)
	var sc := part.global_transform.basis.get_scale()
	_focus_r = HOVER_PX * px_world / maxf((sc.x + sc.y + sc.z) / 3.0, 0.0001)
	_hovering = true
	_overlays()
	_hovering = false


const HOVER_PX := 110.0
var _focus := Vector3.INF          # the hovered spot (the part's space)
var _focus_r := 0.0
var _focus_seeds := PackedInt32Array()
var _last_hit := Vector3.ZERO
var _hover_ms := 0
var _hover_due := false


func _pick_tri(at: Vector2) -> int:
	if _em_tm == null:
		_wait_tm()
	if _em_tm == null:
		_em_tm = em.triangle_mesh()
	var r := view.ray(at)
	var inv := part.global_transform.affine_inverse()
	var hit := _em_tm.intersect_ray(inv * (r[0] as Vector3), (inv.basis * (r[1] as Vector3)).normalized())
	if not hit.is_empty():
		_last_hit = hit["position"]
	return int(hit.get("face_index", -1)) if not hit.is_empty() else -1


func _screen(p: int) -> Vector2:
	return view.project(part.global_transform * (em.points[p] as Vector3))


func click_select(at: Vector2, add: bool) -> void:
	if mode == "object":
		var p := _pick_part(at)
		if p:
			select_part(p, add)
			_show_surface(_surface_of_face(p, _pick_face))   # (the material clicked on, in the panel)
			curve_tools.solid_chosen(p if not add else null)
		elif not add:
			curve_tools.solid_chosen(null)
			part = null
			sel_parts = []
			_fill_parts()
			_show_part()
			_show_material_list()
			_update_ui()
		return
	var t := _pick_tri(at)
	if not add:
		sel_p.fill(0)
		sel_e.fill(0)
		sel_t.fill(0)
		sel_pa.fill(0)
	match sel_kind:
		3:
			var pick := _auto_pick(at)
			match int(pick[0]):
				0:
					var p: int = pick[1]
					var st := 0 if add and sel_pa[p] else 1
					_twin_set = {p: true}
					_twins(0, p, st)
					for q in _twin_set:
						sel_pa[q] = st
				1:
					var e: int = pick[1]
					sel_e[e] = 0 if add and sel_e[e] else 1
					_twins(1, e, sel_e[e])
				2:
					_set_poly(pick[1], 0 if add and sel_t[pick[1]] else 1)
		0:
			var best := -1
			if t >= 0:
				var bd := INF
				for k in 3:
					var p: int = em.tris[t * 3 + k]
					var d := _screen(p).distance_to(at)
					if d < bd:
						bd = d
						best = p
			else:
				var bd := GRAB_POINT_PX * GRAB_POINT_PX
				var g := part.global_transform
				for p in em.points.size():
					var w: Vector3 = g * (em.points[p] as Vector3)
					if view.behind(w):
						continue
					var d := view.project(w).distance_squared_to(at)
					if d < bd:
						bd = d
						best = p
			if best >= 0:
				sel_p[best] = 0 if add and sel_p[best] else 1
				_twins(0, best, sel_p[best])
		1:
			if t >= 0:
				# (the nearest side of the face under the mouse - its diagonals aren't edges you see)
				var loop: PackedInt32Array = em.poly_loop(t) if not view.show_tris else PackedInt32Array()
				if loop.is_empty():
					loop = em.tris.slice(t * 3, t * 3 + 3)
				var best := -1
				var bd := INF
				for k in loop.size():
					var a: int = loop[k]
					var b: int = loop[(k + 1) % loop.size()]
					var q := Geometry2D.get_closest_point_to_segment(at, _screen(a), _screen(b))
					var d := q.distance_to(at)
					if d < bd:
						bd = d
						best = em.edge(a, b)
				if best >= 0:
					sel_e[best] = 0 if add and sel_e[best] else 1
					_twins(1, best, sel_e[best])
		2:
			if t >= 0:
				_set_poly(t, 0 if add and sel_t[t] else 1)
	_derive_sel()
	_overlays()


# --- Auto select (4): a click picks what's under it - a point, else an edge, else the face ---------

## The points picked as points in Auto (sel_p: theirs and those of the edges and faces picked).
var sel_pa := PackedByteArray()
var _auto_btn: Button
const AUTO_POINT_PX := 14.0   # (generous: a point is small - and edge-on after the view turns)
const AUTO_EDGE_PX := 9.0
const GRAB_POINT_PX := 18.0   # a press this near a selected point starts dragging the selection
const GRAB_EDGE_PX := 10.0


## Auto select's toolbar button.
func _auto_select_button() -> Button:
	var b := Button.new()
	b.name = "AutoSelectButton"
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.pressed.connect(func(): set_kind(3))
	_auto_btn = b
	return EditorIcons.dress(b, "m_auto_select", EditorIcons.tip("Auto select", "4",
		"Edit mode: a click picks what's under the mouse - a point when it's on one, else an edge\nwhen it's on one, else the face (shown before you click). Shift+click adds; a box picks the\npoints in it, the edges and the faces wholly in it. Points, edges and faces mixed are moved together."))


## What a click at `at` picks in Auto: [0, point] / [1, edge] / [2, triangle (its face)] / [-1, -1].
func _auto_pick(at: Vector2) -> Array:
	var t := _pick_tri(at)
	if t < 0:
		return [-1, -1]
	var loop: PackedInt32Array = em.poly_loop(t) if not view.show_tris else PackedInt32Array()
	if loop.is_empty():
		loop = em.tris.slice(t * 3, t * 3 + 3)
	var best := -1
	var bd := AUTO_POINT_PX
	for p in loop:
		var d := _screen(p).distance_to(at)
		if d < bd:
			bd = d
			best = p
	if best >= 0:
		return [0, best]
	bd = AUTO_EDGE_PX
	for k in loop.size():
		var a: int = loop[k]
		var b: int = loop[(k + 1) % loop.size()]
		var d := Geometry2D.get_closest_point_to_segment(at, _screen(a), _screen(b)).distance_to(at)
		if d < bd:
			bd = d
			best = em.edge(a, b)
	if best >= 0:
		return [1, best]
	return [2, t]


## Auto: what a click at `at` would pick, shown faintly (`at` x < 0: nothing).
func _auto_preview(at: Vector2) -> void:
	var pts := PackedVector3Array()
	var kind := -1
	if sel_kind == 3 and at.x >= 0.0 and knife.is_empty():
		var pick := _auto_pick(at)
		kind = pick[0]
		var g := part.global_transform
		match kind:
			0: pts.append(g * (em.points[pick[1]] as Vector3))
			1:
				pts.append(g * (em.points[em.edges[int(pick[1]) * 2]] as Vector3))
				pts.append(g * (em.points[em.edges[int(pick[1]) * 2 + 1]] as Vector3))
			2:
				for u in em.poly_tris(pick[1]):
					for k in 3:
						pts.append(g * (em.points[em.tris[u * 3 + k]] as Vector3))
	if kind != view.pre_kind or pts != view.pre_pts:
		view.pre_kind = kind
		view.pre_pts = pts
		view.queue_redraw()


## Triangle `t`'s whole face (n-gon) selected (`state` 1) or not - and with symmetry on, its twins.
func _set_poly(t: int, state: int) -> void:
	sel_t[t] = state
	_twin_set = {t: true}
	_twins(2, t, state)
	for g in _twin_set.keys():
		for u in em.poly_tris(g):
			sel_t[u] = state


## (The elements _twins set last: one and its mirror twins.)
var _twin_set := {}


## Symmetry on: element `idx` (`kind` 0 point / 1 edge / 2 face) has its mirror twin across
## each symmetry axis (and across two or three of them) set to `state` too.
func _twins(kind: int, idx: int, state: int) -> void:
	if not sym.has(true) or em == null:
		return
	var group := [idx]
	for a in 3:
		if not sym[a]:
			continue
		var m := _mirror_map(a)
		var more := []
		for i in group:
			var j := _twin_of(kind, i, m)
			if j >= 0 and not j in group and not j in more:
				more.append(j)
		group += more
	var arr: PackedByteArray = [sel_p, sel_e, sel_t][kind]
	_twin_set.clear()
	for i in group:
		arr[i] = state
		_twin_set[i] = true
	match kind:
		0: sel_p = arr
		1: sel_e = arr
		2: sel_t = arr


func _twin_of(kind: int, i: int, m: PackedInt32Array) -> int:
	match kind:
		0:
			return m[i]
		1:
			var a: int = m[em.edges[i * 2]]
			var b: int = m[em.edges[i * 2 + 1]]
			return em.edge(a, b) if a >= 0 and b >= 0 else -1
		2:
			var k := []
			for c in 3:
				var q: int = m[em.tris[i * 3 + c]]
				if q < 0:
					return -1
				k.append(q)
			var ks := k.duplicate()
			ks.sort()
			var exact: int = int(_tri_index().get(Vector3i(ks[0], ks[1], ks[2]), -1))
			if exact >= 0:
				return exact
			# (its mirror split into triangles the other way: the triangle sharing most of the
			# twinned points, then the nearest to the mirror image's middle)
			var want: Vector3 = (em.points[k[0]] + em.points[k[1]] + em.points[k[2]]) / 3.0
			var best := -1
			var best_score := -INF
			for q in k:
				for t in _tris_at.get(q, []):
					var shared := 0
					for c in 3:
						if em.tris[t * 3 + c] in k:
							shared += 1
					var mid: Vector3 = (em.points[em.tris[t * 3]] + em.points[em.tris[t * 3 + 1]] + em.points[em.tris[t * 3 + 2]]) / 3.0
					var score := shared * 1000.0 - mid.distance_to(want)
					if score > best_score:
						best_score = score
						best = t
			return best
	return -1


var _mm := {}           # axis -> the points' mirror map (for the mesh as it is now)
var _mm_key := ""
var _tri_of := {}       # Vector3i(sorted points) -> triangle


func _sym_key() -> String:
	return "%d|%d|%d|%s" % [em.get_instance_id(), em.topo, em.points.size(), em.points[0] if em.points.size() > 0 else Vector3.ZERO]


func _mirror_map(a: int) -> PackedInt32Array:
	_sym_ref()   # (twins paired where the sides last matched - not where one side's been moved to)
	if not _mm.has(a):
		var size: float = em.aabb().size.length()
		var now: PackedVector3Array = em.points
		em.points = _ref_pts
		_mm[a] = em.mirror_map(a, maxf(size * 0.0005, 0.0005))
		em.points = now
	return _mm[a]


func _tri_index() -> Dictionary:
	if _tri_of.is_empty():
		_tris_at.clear()
		for t in em.tri_count():
			var k := [em.tris[t * 3], em.tris[t * 3 + 1], em.tris[t * 3 + 2]]
			for q in k:
				if not _tris_at.has(q):
					_tris_at[q] = []
				_tris_at[q].append(t)
			k.sort()
			_tri_of[Vector3i(k[0], k[1], k[2])] = t
	return _tri_of


var _tris_at := {}      # point -> its triangles


var _edit_count := 0    # (each edit: the mirror maps made again when next needed)


func box_select(r: Rect2, add: bool) -> void:
	r = r.abs()
	if mode == "object":
		return
	var inside := PackedByteArray()
	inside.resize(em.points.size())
	var g := part.global_transform
	for p in em.points.size():
		var w: Vector3 = g * (em.points[p] as Vector3)
		if not view.behind(w) and r.has_point(view.project(w)):
			inside[p] = 1
	if not add:
		sel_p.fill(0)
		sel_e.fill(0)
		sel_t.fill(0)
	if sel_kind == 3 and not add:
		sel_pa.fill(0)
	match sel_kind:
		3:
			for p in inside.size():
				if inside[p]:
					sel_pa[p] = 1
			for e in em.edge_count():
				if inside[em.edges[e * 2]] and inside[em.edges[e * 2 + 1]] and (view.show_tris or not em.edge_inner[e]):
					sel_e[e] = 1
			for t in em.tri_count():
				if inside[em.tris[t * 3]] and inside[em.tris[t * 3 + 1]] and inside[em.tris[t * 3 + 2]]:
					sel_t[t] = 1
			em.close_to_polys(sel_t)
		0:
			for p in inside.size():
				if inside[p]:
					sel_p[p] = 1
		1:
			for e in em.edge_count():
				if inside[em.edges[e * 2]] and inside[em.edges[e * 2 + 1]] and (view.show_tris or not em.edge_inner[e]):
					sel_e[e] = 1
		2:
			for t in em.tri_count():
				if inside[em.tris[t * 3]] and inside[em.tris[t * 3 + 1]] and inside[em.tris[t * 3 + 2]]:
					sel_t[t] = 1
			em.close_to_polys(sel_t)
	if sym.has(true):   # (symmetry on: the box's mirror images too)
		for kind in ([0, 1, 2] if sel_kind == 3 else [sel_kind]):
			var arr: PackedByteArray = [sel_pa if sel_kind == 3 else sel_p, sel_e, sel_t][kind]
			var ids := []
			for i in arr.size():
				if arr[i]:
					ids.append(i)
			for i in ids:
				_twin_set = {}
				_twins(kind, i, 1)
				if kind == 0 and sel_kind == 3:
					for q in _twin_set:
						sel_pa[q] = 1
	_derive_sel()
	_overlays()


func frame_selected() -> void:
	if em and part:
		var ids := selected_points()
		if not ids.is_empty():
			var g := part.global_transform
			var b := AABB(g * (em.points[ids[0]] as Vector3), Vector3.ZERO)
			for p in ids:
				b = b.expand(g * (em.points[p] as Vector3))
			view.frame(b.grow(0.05))
			return
	if part:
		view.frame(part.global_transform * part.get_aabb())
		return
	frame_all()


func frame_all() -> void:
	var b := AABB()
	var first := true
	for p: MeshInstance3D in parts():
		var a := p.global_transform * p.get_aabb() if p.is_inside_tree() else p.get_aabb()
		b = a if first else b.merge(a)
		first = false
	if first:
		b = AABB(Vector3(-1, 0, -1), Vector3(2, 2, 2))
	view.frame(b)


# --- input ---------------------------------------------------------------------

## The view's mouse: left click selects (a part; in edit mode its points / edges / faces), left drag
## in empty space turns the view round, left drag starting on the model in edit mode (or Shift+drag
## anywhere) draws a selection box; right click: the menu (menu()), right drag pans; middle drag
## turns (Shift: pans); the wheel zooms (while moving with proportional editing: its radius).
func _view_input(e: InputEvent) -> void:
	if mesh_ops.view_input(e):   # (the loop cut's hover and click; Alt+click: a loop)
		view.accept_event()
		return
	if curve_tools.view_input(e):   # (sketching, the curves' points dragged, extrude's drag)
		view.accept_event()
		return
	var mm := e as InputEventMouseMotion
	if mm:
		_mouse = mm.position
		if _drag == "orbit":
			view.orbit(mm.relative, _orbit_pivot())
		elif _drag == "pan":
			if _pan_depth == 0.0:
				_pan_depth = view.depth_at(_zoom_point(mm.position - mm.relative))   # (what's under the mouse: held under it)
			view.pan(mm.relative, _pan_depth)
		elif not xf.is_empty():
			if not deform.hover(mm.position):   # (curve deform: only a dragged handle works the step out)
				_xf_update()
		elif _rpress.x >= 0 and (mm.position - _rpress).length() > 5.0:
			_drag = "pan"
			_pan_depth = view.depth_at(_zoom_point(_rpress))
			_rpress = Vector2(-1, -1)
		elif _press.x >= 0 and (mm.position - _press).length() > 5.0:
			if _press_move:
				_drag_move(mm.position)
			elif _press_box:
				_drag = "box"
				view.box = Rect2(_press, mm.position - _press)
				view.queue_redraw()
			else:
				_drag = "orbit"
				_press = Vector2(-1, -1)
				view.orbit(mm.relative, _orbit_pivot())
		elif _drag == "box":
			view.box = Rect2(_press, mm.position - _press)
			view.queue_redraw()
		elif mode == "edit" and _drag == "":
			_hover(mm.position)
			if not knife.is_empty():
				_knife_show(mm.position)
		if xf.is_empty() and _drag == "" and knife.is_empty():
			var hot: String = view.gizmo_pick(mm.position).get("id", "")
			if hot != view.gizmo_hot:
				view.gizmo_hot = hot
				view.queue_redraw()
		return
	var mb := e as InputEventMouseButton
	if mb == null:
		return
	_mouse = mb.position
	view.accept_event()
	if mb.pressed:
		_drag_started += 1   # (what the view turns about worked out again for this drag)
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		if not mb.pressed:
			return
		var up := mb.button_index == MOUSE_BUTTON_WHEEL_UP
		if not xf.is_empty() and prop_on and mode == "edit":
			set_radius(prop_radius * (1.0 / 1.15 if up else 1.15))
		else:
			view.zoom(1.0 / 1.12 if up else 1.12, _zoom_point(mb.position))
		return
	if mb.button_index == MOUSE_BUTTON_MIDDLE or (mb.button_index == MOUSE_BUTTON_LEFT and mb.alt_pressed and xf.is_empty()):
		_drag = ("pan" if mb.shift_pressed else "orbit") if mb.pressed else ""
		_pan_depth = 0.0   # (worked out on the first move)
		return
	if not knife.is_empty():
		# (the knife: a left click places a point, a right click stops)
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if not knife_add(mb.position, not mb.ctrl_pressed):
				_say("Knife: click on the solid.")
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			knife_cancel()
			_say("Knife stopped.")
		return
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if mb.pressed:
			if not xf.is_empty():
				_cancel_xf()
				return
			_rpress = mb.position
		else:
			if _drag == "pan":
				_drag = ""
			elif _rpress.x >= 0:
				menu(mb.position)
			_rpress = Vector2(-1, -1)
		return
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if deform.mouse_button(mb):   # (curve deform: its ends and handles dragged)
		return
	if not mb.pressed and _gizmo_drag:
		_gizmo_drag = false
		if not xf.is_empty():
			confirm_transform()
		_sync_gizmo()
		return
	if mb.pressed:
		if not xf.is_empty():
			confirm_transform()
			return
		var h := view.gizmo_pick(mb.position)
		if not h.is_empty():
			_gizmo_drag = true
			begin_transform(h["kind"], h["axis"])
			var hid: String = h["id"]
			if hid.length() == 2:
				xf["axis_k"] = "xyz".find(hid[1])   # (the gizmo's own axis: its colour and name)
			_sync_gizmo()
			return
		_press = mb.position
		# (a drag from the model in edit mode - or with Shift - selects with a box; from empty space it turns the view)
		_press_box = mb.shift_pressed or (mode == "edit" and _pick_part(mb.position) != null)
		# (a drag that starts on what's selected moves it - along the axis the drag goes)
		_press_move = not mb.shift_pressed and _on_selection(mb.position)
	else:
		if _drag == "box":
			box_select(view.box, mb.shift_pressed)
			view.box = Rect2()
			view.queue_redraw()
		elif _drag == "orbit":
			pass
		elif _press.x >= 0:
			click_select(mb.position, mb.shift_pressed or mb.ctrl_pressed)
		_drag = ""
		_press = Vector2(-1, -1)


var _press_move := false
## How a drag on the selection moves it: "smart" - along the one of its own axes the drag goes
## (along its surface, across it, its normal); "perspective" - freely over the plane the view
## looks at most squarely (the ground from above, the upright one facing you...), snapping to
## one of that plane's axes while the drag runs along it.
var move_mode := "smart"
var _move_btns := {}
const SNAP_DEG := 9.0


func set_move_mode(m: String) -> void:
	move_mode = m
	for k in _move_btns:
		(_move_btns[k] as Button).set_pressed_no_signal(k == m)
	var c := ConfigFile.new()
	c.load(LAYOUT)
	c.set_value("mesh", "move_mode", m)
	c.save(LAYOUT)
	_say("Drag moves: " + ("smart axis - along the selection's own axis the drag goes." if m == "smart" else "perspective - freely over the plane you're looking at, snapping to its axes."))


## A perspective move's step: the mouse followed over the plane (world axes) the view looks at most
## squarely, through what's moving; while the drag runs within SNAP_DEG of one of the plane's two axes
## on screen, along that axis only (drawn).
func _perspective_step(pivot: Vector3, m0: Vector2, m: Vector2) -> Vector3:
	var n: Vector3 = xf["plane"]
	var p0 = view.on_plane(m0, pivot, n)
	var p1 = view.on_plane(m, pivot, n)
	if p0 == null or p1 == null:
		return Vector3.ZERO
	var d: Vector3 = p1 - p0
	view.axis_line = {}
	var drag := m - m0
	if drag.length() > 8.0:
		var c := view.project(pivot)
		for k in 3:
			var ax: Vector3 = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][k]
			if absf(ax.dot(n)) > 0.5:
				continue   # (the plane's normal: not one of its axes)
			var sd := view.project(pivot + ax * 0.1) - c
			if sd.length() < 0.5:
				continue
			if absf(rad_to_deg(drag.angle_to(sd))) < SNAP_DEG or absf(rad_to_deg(drag.angle_to(-sd))) < SNAP_DEG:
				d = ax * d.dot(ax)
				view.axis_line = {"at": pivot, "dir": ax, "col": MeshView.AXIS_COL[k]}
				view.hint = "on " + "XYZ"[k] + "  "
				return d
	view.hint = "on the " + {0: "side (YZ)", 1: "ground (XZ)", 2: "front (XY)"}[int(xf["plane_k"])] + " plane  "
	return d
var _header: Control
var _col: Control
var _toolbar: HFlowContainer
var _left_panel: Control
var _right_panel: Control
var _left_btn: Button
var _right_btn: Button
var _max_btn: Button
var left_shown := true
var right_shown := true
var maximized := false


func _panel_toggle(icon: String, name: String, keys: String, help: String, cb: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = true
	b.focus_mode = Control.FOCUS_NONE
	b.icon = EditorIcons.get_icon(icon)
	b.tooltip_text = EditorIcons.tip(name, keys, help)
	b.toggled.connect(func(_on): cb.call())
	IconAnim.attach(b, icon)
	return _compact(b)


## The left panel (models, shapes, parts) shown or collapsed (remembered).
func set_left_panel(on: bool) -> void:
	left_shown = on
	_apply_panels()
	_save_panels()


## The right panel (the part, edit mesh, booleans, shapes, mirror, material) shown or collapsed (remembered).
func set_right_panel(on: bool) -> void:
	right_shown = on
	_apply_panels()
	_save_panels()


## The 3D view filling the screen: both panels, the toolbar and Talos's header and rail hidden - or all back.
func set_maximized(on: bool) -> void:
	maximized = on
	_apply_panels()


func _apply_panels() -> void:
	if _left_panel == null:
		return
	_left_panel.visible = left_shown and not maximized
	_right_panel.visible = right_shown and not maximized
	_toolbar.visible = not maximized
	_header.visible = not maximized
	if not embedded and _col and _col.get_parent():
		for c in _col.get_parent().get_children():   # (Talos's rail and its divider beside the screen)
			if c != _col:
				(c as CanvasItem).visible = not maximized
	_left_btn.set_pressed_no_signal(left_shown)
	_right_btn.set_pressed_no_signal(right_shown)
	_max_btn.icon = EditorIcons.get_icon("m_restore" if maximized else "m_maximize")
	_left_btn.visible = not maximized   # (maximised: no panels to show - the button above brings them back)
	_right_btn.visible = not maximized
	_max_btn.tooltip_text = EditorIcons.tip("Restore the view" if maximized else "Maximise the view", "Ctrl+M",
		"Everything back: the panels, the toolbar, Talos's header and rail." if maximized else "The 3D view fills the screen: the side panels, the toolbar and Talos's header and rail hidden.\nAgain: everything back.")
	if view:
		view.request()


func _save_panels() -> void:
	var c := ConfigFile.new()
	c.load(LAYOUT)
	c.set_value("mesh", "left_shown", left_shown)
	c.set_value("mesh", "right_shown", right_shown)
	c.save(LAYOUT)
var _sel_version := 0     # (each selection change or edit: the selection's frame worked out again when next needed)
var _frame_key := -1
var _frame := Basis()


## The selection's own axes (global): X along its surface, Y across it, Z its normal - the
## selected faces' normals (area-weighted), else those of the faces round the selected points;
## X a selected edge's direction laid on the surface, else the world's up (or right) laid on it.
## Object mode: the part's own axes.
func sel_frame() -> Basis:
	if mode == "object" or em == null or part == null:
		return part.global_basis.orthonormalized() if part else Basis()
	if _frame_key == _sel_version:
		return _frame
	_frame_key = _sel_version
	var g := part.global_transform
	var n := Vector3.ZERO
	var nt: int = em.tri_count()
	var any_face := false
	for t in mini(nt, sel_t.size()):
		if sel_t[t]:
			any_face = true
			break
	for t in nt:
		var take := false
		if any_face:
			take = t < sel_t.size() and sel_t[t] == 1
		else:
			for k in 3:
				if sel_p[em.tris[t * 3 + k]]:
					take = true
					break
		if not take:
			continue
		var a: Vector3 = em.points[em.tris[t * 3]]
		var b: Vector3 = em.points[em.tris[t * 3 + 1]]
		var c: Vector3 = em.points[em.tris[t * 3 + 2]]
		n += (b - a).cross(c - a)   # (its length: twice its area - bigger faces count more)
	n = (g.basis * n)
	if n.length() < 1e-9:
		_frame = Basis()
		return _frame
	n = n.normalized()
	var x := Vector3.ZERO
	for e in mini(em.edge_count(), sel_e.size()):
		if sel_e[e]:
			var d: Vector3 = g.basis * ((em.points[em.edges[e * 2 + 1]] as Vector3) - (em.points[em.edges[e * 2]] as Vector3))
			x = d - n * d.dot(n)
			if x.length() > 1e-6:
				break
	if x.length() < 1e-6:
		var w := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		x = w - n * w.dot(n)
	x = x.normalized()
	var y := n.cross(x).normalized()
	_frame = Basis(x, y, n)
	return _frame
var _sel_spins: Array = []
var _sel_count: Label
var _sel_syncing := false
var _sel_shown_ms := 0


## The selection's coordinates shown (live: at most 30 times a second while it moves).
func _sync_sel_coords(force := false) -> void:
	if _sel_spins.is_empty():
		return
	var now := Time.get_ticks_msec()
	if not force and now - _sel_shown_ms < 33:
		return
	_sel_shown_ms = now
	var sel := selected_points() if em and mode == "edit" else PackedInt32Array()
	_sel_syncing = true
	var c: Vector3 = em.centroid(sel) if not sel.is_empty() else Vector3.ZERO
	for a in 3:
		var sp: SpinBox = _sel_spins[a]
		sp.editable = not sel.is_empty()
		sp.set_value_no_signal(snappedf(c[a], 0.0001))
	_sel_count.text = str(sel.size()) if not sel.is_empty() else "-"
	_sel_syncing = false


func _sel_coord_typed(a: int, v: float) -> void:
	if _sel_syncing or em == null:
		return
	var sel := selected_points()
	if sel.is_empty():
		return
	var d := Vector3.ZERO
	d[a] = v - em.centroid(sel)[a]
	if absf(d[a]) > 1e-7:
		move_selection(d)
	_sync_sel_coords(true)


## A press on what's selected (object mode: the selected part; edit mode: a face, edge or
## point of the selection).
func _on_selection(at: Vector2) -> bool:
	if mode == "object":
		return part != null and _pick_part(at) == part
	if em == null:
		return false
	var sel := selected_points()
	if sel.is_empty():
		return false
	# Near a selected point or edge on screen: on it - with or without a face under the mouse
	# (a point on the outline, an edge seen edge-on after the view turns).
	var g := part.global_transform
	var near2 := GRAB_POINT_PX * GRAB_POINT_PX
	var step := maxi(1, sel.size() / 4000)   # (a huge selection: every so many points)
	for i in range(0, sel.size(), step):
		var w: Vector3 = g * (em.points[sel[i]] as Vector3)
		if not view.behind(w) and view.project(w).distance_squared_to(at) <= near2:
			return true
	var ne: int = mini(em.edge_count(), sel_e.size())
	if sel.size() < 4000:
		for e in ne:
			if not sel_e[e]:
				continue
			var a: Vector3 = g * (em.points[em.edges[e * 2]] as Vector3)
			var b: Vector3 = g * (em.points[em.edges[e * 2 + 1]] as Vector3)
			if view.behind(a) or view.behind(b):
				continue
			var q := Geometry2D.get_closest_point_to_segment(at, view.project(a), view.project(b))
			if q.distance_to(at) <= GRAB_EDGE_PX:
				return true
	var t := _pick_tri(at)
	if t < 0:
		return false
	for k in 3:
		if sel_p[em.tris[t * 3 + k]]:
			return true
	return false


## The drag from a press on the selection: a perspective move (move_mode "perspective"), or a smart
## axis move - along the axis (X, Y or Z)
## whose direction on screen is the closest to the drag's (the same move as G with that
## axis: proportional editing, symmetry, undo); letting go keeps it.
func _drag_move(now: Vector2) -> void:
	if move_mode == "perspective":
		_mouse = _press
		_press = Vector2(-1, -1)
		_gizmo_drag = true
		begin_transform("G")
		var fwd: Vector3 = -view.cam.global_basis.z
		var best_k := 1
		for k in 3:
			if absf(fwd[k]) > absf(fwd[best_k]):
				best_k = k
		xf["plane"] = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][best_k]   # (the plane the view looks at most squarely)
		xf["plane_k"] = best_k
		_mouse = now
		_xf_update()
		return
	var pivot: Vector3
	if mode == "object":
		pivot = part.global_position
	else:
		pivot = part.global_transform * em.centroid(selected_points())
	var d := (now - _press).normalized()
	var c := view.project(pivot)
	var f := sel_frame()
	var best: Vector3 = f.x.normalized()
	var best_k := 0
	var bd := -1.0
	for k in 3:
		var ax: Vector3 = f[k].normalized()
		var sdir := view.project(pivot + ax * 0.1) - c
		if sdir.length() < 0.5:
			continue   # (an axis pointing at the camera: not one a drag across the screen means)
		var al := absf(d.dot(sdir.normalized()))
		if al > bd:
			bd = al
			best = ax
			best_k = k
	_mouse = _press
	_press = Vector2(-1, -1)
	_gizmo_drag = true   # (letting go keeps it, as the gizmo's drag)
	begin_transform("G", best)
	xf["axis_k"] = best_k   # (its colour and name: along the surface X, across it Y, the normal Z)
	_mouse = now
	_xf_update()
	_say("Moving along %s (as you drag) - let go to keep it, right-click to cancel." % (["its surface (X)", "across its surface (Y)", "its normal (Z)"][best_k] if mode == "edit" else "its own " + "XYZ"[best_k]))


var _rpress := Vector2(-1, -1)
var _pan_depth := -1.0   # (a pan: how far ahead the model under the mouse was when it began; 0 - not looked yet)
var _press_box := false
var _menu: PopupPanel


## The right-click menu at `at` (the view's point): icons only - each with its tooltip -
## in groups for what can be done now: the part under the mouse picked first (object
## mode); edit mode's tools on its selection.
func menu(at: Vector2) -> PopupPanel:
	if mode == "object":
		var p := _pick_part(at)
		if p and not p in selected_parts():
			var prev := part
			select_part(p)
			_menu_prev = prev   # (the one selected before: a boolean's A, this one its B)
			_update_ui()
	if _menu and is_instance_valid(_menu):
		_menu.queue_free()
	_menu = PopupPanel.new()
	_menu.name = "MeshMenu"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_menu.add_child(box)
	var groups := mesh_menu_groups(mode)
	# One page, only what fits what's picked: an ECurve object's faces, edges or vertices picked - their
	# tools; a solid selected - the solid's; nothing - drawing and adding; the view's and history's always.
	var ct = curve_tools
	var curve_pick: bool = not ct.sel.is_empty() or not ct.picked_points().is_empty() or not ct.picked_patch().is_empty() or ct.picked_solid() != null or not ct.point_items(at).is_empty() or ct.active()
	var general: Array = groups[groups.size() - 1]
	var page_groups := []
	if curve_pick or part == null:
		page_groups = ct.menu_groups(at)
	else:
		page_groups = groups.slice(0, groups.size() - 1)
		for g in ct.menu_groups(at):
			for it in g:
				if str(it[1]) in ["Bake solid", "Auto join", "Merge by distance"]:
					page_groups.append([it])
	page_groups.append(general)
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 4)
	page.name = "Page"
	box.add_child(page)
	_menu_page(page, page_groups, "ecurve")
	add_child(_menu)
	# (where it fits: its size measured, then kept inside the window - shifted left / up from the edges)
	var sz := Vector2(_menu.get_contents_minimum_size())
	var win := get_viewport().get_visible_rect().size
	var pos := view.get_global_rect().position + at
	pos.x = clampf(pos.x, 4.0, maxf(4.0, win.x - sz.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, win.y - sz.y - 4.0))
	_menu.popup(Rect2i(Vector2i(pos), Vector2i(sz)))
	_fit_menu.call_deferred()   # (again with its real size, once it's laid out)
	_menu.popup_hide.connect(_menu_hidden.bind(_menu))
	# (a glint running round its edge - on the panel's own border, out past the content's margins)
	var shine: Control = load("res://scripts/ui/edge_shine.gd").call("add_to", _menu)
	var sb := _menu.get_theme_stylebox("panel")
	if sb:
		shine.set("inset", 1.5 - sb.get_margin(SIDE_LEFT))
	_menu_fold.call_deferred(_menu, true)   # (unfolds from where you clicked, once it has its size)
	return _menu


## The right-click menu folding open from where it was clicked (_menu_unroll); shut: _menu_close.
func _menu_fold(m: PopupPanel, open: bool) -> void:
	if m == null or not is_instance_valid(m) or not m.visible:
		return
	if open:
		_fit_menu()
		_menu_unroll(m)
	else:
		_menu_close(m)


## (opening) A window can't be drawn smaller than what's in it - so a stand-in panel in its look and
## place unrolls down from the top while the menu's own panel waits see-through and its icons fold
## open row by row (scaled from the top) and fade in; then the menu shows as itself.
func _menu_unroll(m: PopupPanel) -> void:
	var sb := m.get_theme_stylebox("panel")
	var box: Control = m.get_child(0) as Control if m.get_child_count() > 0 else null
	m.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var ghost := Panel.new()
	ghost.name = "MenuFoldIn"
	ghost.top_level = true
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if sb:
		ghost.add_theme_stylebox_override("panel", sb)
	ghost.position = Vector2(m.position)
	ghost.size = Vector2(m.size.x, 4)
	add_child(ghost)
	var h := float(m.size.y)
	if box:
		box.pivot_offset = Vector2.ZERO
		box.scale = Vector2(1, 0.02)
		box.modulate.a = 0.0
	# (by their ids: the menu may be gone before the fold ends - a lambda holding it would hold freed things)
	var mid := m.get_instance_id()
	var bid := box.get_instance_id() if box else 0
	var tw := ghost.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(_unroll_step.bind(ghost.get_instance_id(), mid, bid, h), 0.0, 1.0, 0.5)
	tw.tween_callback(_unroll_end.bind(ghost.get_instance_id(), mid, bid))


func _unroll_step(f: float, gid: int, mid: int, bid: int, h: float) -> void:
	var ghost := instance_from_id(gid) as Control
	var m := instance_from_id(mid) as Window
	var box := instance_from_id(bid) as Control
	if ghost:
		ghost.size = Vector2(ghost.size.x, maxf(4.0, h * f))
		if m:
			ghost.position = Vector2(m.position)
	if box:
		box.scale = Vector2(1, maxf(0.02, f))
		box.modulate.a = clampf(f * 1.5 - 0.3, 0.0, 1.0)


func _unroll_end(gid: int, mid: int, bid: int) -> void:
	var m := instance_from_id(mid) as Window
	if m:
		m.remove_theme_stylebox_override("panel")
	var box := instance_from_id(bid) as Control
	if box:
		box.scale = Vector2.ONE
		box.modulate.a = 1.0
	var ghost := instance_from_id(gid) as Node
	if ghost:
		ghost.queue_free()


## The menu folded shut, then gone (its stand-in rolls up where it was - _menu_hidden).
func _menu_close(m: PopupPanel) -> void:
	if m == null or not is_instance_valid(m) or not m.visible:
		return
	m.hide()


## (closed by a click elsewhere or Esc - hidden at once by the popup itself) its fold played by a
## stand-in: a panel in its look and place, rolling up and fading, then gone.
func _menu_hidden(m: PopupPanel) -> void:
	if not is_instance_valid(m) or m.has_meta("closing") or m.is_queued_for_deletion():
		return
	m.set_meta("closing", true)
	var ghost := Panel.new()
	ghost.name = "MenuFoldOut"
	ghost.top_level = true
	ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := m.get_theme_stylebox("panel")
	if sb:
		ghost.add_theme_stylebox_override("panel", sb)
	ghost.position = Vector2(m.position)
	ghost.size = Vector2(m.size)
	add_child(ghost)
	var h := float(m.size.y)
	var tw := ghost.create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_method(func(f: float):
		ghost.size = Vector2(ghost.size.x, maxf(4.0, h * f))
		ghost.modulate.a = clampf(f * 1.4, 0.0, 1.0), 1.0, 0.0, 0.4)
	tw.tween_callback(ghost.queue_free)


## What the right-click menu has isn't shown anywhere else: every icon button of the toolbar, the side
## panels and the header (not the variants') whose icon one of the menu's tools has is hidden - it
## still works (its keys, its state), the menu is where it's used from.
func hide_menu_twins() -> void:
	var icons := {}
	for g in mesh_menu_groups("object") + mesh_menu_groups("edit") + [curve_tools.every_menu_item()]:
		for it in g:
			icons[EditorIcons.get_icon(str(it[0]))] = true
	var roots: Array = [_toolbar, _right_tabs, _header]
	for r in roots:
		if r == null or not is_instance_valid(r):
			continue
		for b in (r as Node).find_children("*", "Button", true, false):
			if b in _variant_btns or b is OptionButton or b is CheckBox:
				continue
			var ic: Texture2D = (b as Button).icon
			if b.has_meta("icon_anim") and (b.get_meta("icon_anim") as Object).get("tex") != null and (b.get_meta("icon_anim") as Object).get("_amt") > 0.0:
				ic = (b.get_meta("icon_anim") as Object).get("tex")
			if ic != null and icons.has(ic):
				(b as Button).visible = false


## The right-click menu's Mesh page: its groups of tools for mode `as_mode` ("object" / "edit").
func mesh_menu_groups(as_mode: String) -> Array:
	var groups: Array = []
	var has := part != null
	if as_mode == "object":
		groups.append([
			["m_tpose", "T-pose" + (" off" if is_tposed() else ""), "Ctrl+T", "A character laid out for editing: arms out, its weapon beside it (saved in its own pose).", toggle_tpose, true],
			["m_weapons", "Hide weapons" if weapons_shown else "Show weapons", "Ctrl+W", "The model's weapons hidden or shown (still saved).", func(): set_weapons(not weapons_shown), true],
			["m_move", "Move", "G", "Moves the solid with the mouse (X / Y / Z: along an axis; click keeps, right-click cancels).", func(): begin_transform("G"), has],
			["m_rotate", "Turn", "R", "Turns the solid with the mouse (X / Y / Z: about an axis).", func(): begin_transform("R"), has],
			["m_scale", "Scale", "S", "Scales the solid with the mouse (X / Y / Z: along an axis).", func(): begin_transform("S"), has],
			["duplicate", "Duplicate solid", "Shift+D", "A copy of the solid, beside it.", duplicate_part, has],
			["rename", "Rename solid", "", "Its name, in the panel on the right.", func(): (_fields["name"] as LineEdit).grab_focus(), has],
			["eye_off" if has and part.visible else "eye", "Hide / show solid", "", "Hides the solid in the view (or shows it again).", func():
				part.visible = not part.visible; _place_ghosts(); _fill_parts(); view.request(), has],
			["delete", "Delete solid", "X / Delete", "Removes the solid.", delete_part, has],
			["m_bind_auto", "Auto-bind to the skeleton", "", "Skins the solid to the character's skeleton: each vertex to its nearest bones - it moves with the animations.", func(): bind_part(), has and _can_bind()],
			["m_bind_bone", "Bind to bone", "", "Skins the whole solid to one bone (the one picked in the panel, else the nearest) - it moves rigidly with it.", func(): bind_part(null, _picked_bind()), has and _can_bind()],
			["unlock", "Unbind", "", "Lets the solid go of the skeleton: it stays where it's drawn now and no longer animates.", func(): unbind_part(), has and part.has_meta("bound_part")],
			["m_bone_parts", "Solid from bone", "", "A body solid for the bone picked in the panel (else the one nearest the solid): a rounded loft along it, skinned to it.", func(): parts_from_bones("bone"), not _rig().is_empty()],
			["m_bone_parts", "Solids from bone and children", "", "A body solid for that bone and for every bone below it (an arm from the shoulder down).", func(): parts_from_bones("children"), not _rig().is_empty()],
			["m_bone_parts", "Solids from all bones", "", "A body solid for every bone of the skeleton, each skinned to its bone.", func(): parts_from_bones("all"), not _rig().is_empty()],
		])
		var bools := []
		for o in shape_tools.bool_items():
			bools.append([o[0], o[1], o[2], o[3], o[4], o[6]])
		groups.append(bools)
		var mm: Dictionary = part.get_meta("mesh_mirror", {}) if has else {}
		var mir := []
		for a in 3:
			var on: bool = has and (mm.get("axes", []) as Array).has(a)
			mir.append(["m_mirror_" + "xyz"[a], ("Mirror off " if on else "Mirror across ") + "XYZ"[a], "",
				"The mirror modifier: the solid mirrored across its %s axis, live (applied when saved)." % "XYZ"[a], func(): _toggle_mirror(a), has])
		mir.append(["m_mirror_apply", "Apply the mirror", "", "Makes the mirror modifier part of the mesh.", apply_mirror, has and not mm.is_empty()])
		groups.append(mir)
	else:
		groups.append([
			["m_object", "Object mode", "Tab", "Back to whole solids.", toggle_edit, true],
			["m_auto_select", "Auto select", "4", "A click picks what's under the mouse: a point, else an edge, else the face.", func(): set_kind(3), true],
			["m_vertex", "Vertex select", "1", "Pick vertices.", func(): set_kind(0), true],
			["m_edge", "Edge select", "2", "Pick edges.", func(): set_kind(1), true],
			["m_face", "Face select", "3", "Pick faces.", func(): set_kind(2), true],
			["m_sel_all", "Select all", "A", "Selects everything.", func(): select_all(true), true],
			["m_sel_none", "Select none", "Alt+A", "Clears the selection.", func(): select_all(false), true],
			["m_sel_invert", "Invert selection", "", "Selects what isn't, and the other way round.", _invert_selection, true],
			["m_spherize", "Spherize", "Shift+Alt+S", "The selected points pushed onto a sphere round their middle (the mouse sets how far).", spherize, true],
			["m_curve", "Curve deform", "V", "A curve along the selection: drag its ends and handles, the points bend with it (Enter keeps).", func(): deform.begin_curve(), true],
			["m_flatten", "Flatten", "Shift+Alt+F", "The selected points pressed onto their best-fit plane (X / Y / Z: an axis plane; the mouse sets how far).", func(): deform.begin_flatten(), true],
			["m_sel_material", "Material island", "L", "Every face joined to the selected ones that has the same material (up to where another starts).", func(): select_material_island(), true],
			["m_ngons", "Show faces (n-gons)" if view.show_tris else "Show triangles", "", "The wireframe shows the faces - quads and n-gons - or every triangle of them.", func(): set_tris_view(not view.show_tris), true],
		])
		var any := not selected_points().is_empty()
		groups.append([
			["m_move", "Move", "G", "Moves the selection with the mouse (X / Y / Z: along an axis).", func(): begin_transform("G"), any],
			["m_rotate", "Turn", "R", "Turns the selection with the mouse.", func(): begin_transform("R"), any],
			["m_scale", "Scale", "S", "Scales the selection with the mouse.", func(): begin_transform("S"), any],
			["m_extrude", "Extrude", "E", "Pulls new faces out of the selected ones, then moves them.", func(): extrude(), any],
			["m_subdivide", "Subdivide", "", "Splits the selected faces in four.", subdivide, any],
			["m_dissolve", "Dissolve", "Ctrl+X", "Points: the faces round each one made one; edges: the faces either side made one; faces: those side by side made one.", dissolve_selected, any],
			["m_knife", "Knife", "K / Shift+K", "Cuts the faces along a path: click points on the surface, Enter cuts (Shift+K: right through the solid).", func(): begin_knife(), true],
			["m_merge", "Merge", "M", "Joins the selected points into one at their centre.", merge_selected, any],
			["delete", "Delete", "X / Delete", "Removes the selection.", delete_selected, any],
			["m_flip", "Flip normals", "", "Turns the selected faces the other way.", flip_normals, any],
			["m_normals", "Recalculate normals", "", "Points the faces outward again and smooths their shading.", recalc_normals, true],
		])
		groups.append(mesh_ops.menu_items())   # (duplicate, inset, loop cut, select loop / ring, merge by distance)
		groups.append([
			["m_prop", "Proportional editing " + ("off" if prop_on else "on"), "O", "Moving points drags their neighbours along, less the further they are.", func(): _prop_btn.button_pressed = not _prop_btn.button_pressed, true],
			["m_falloff", "Falloff: " + prop_falloff + " (next)", "Shift+O", "How the pull fades with distance.", func():
				_falloff.select((EditMesh.FALLOFFS.find(prop_falloff) + 1) % EditMesh.FALLOFFS.size())
				prop_falloff = EditMesh.FALLOFFS[_falloff.selected]
				_say("Falloff: " + prop_falloff), true],
			["m_connected", "Connected only " + ("off" if prop_connected else "on"), "Alt+O", "Only points joined by edges are pulled.", func(): _connected.button_pressed = not _connected.button_pressed, true],
			["m_sym_x", "Symmetry X " + ("off" if sym[0] else "on"), "", "Edits mirror across X.", func(): sym[0] = not sym[0]; _update_ui(), true],
			["m_sym_y", "Symmetry Y " + ("off" if sym[1] else "on"), "", "Edits mirror across Y.", func(): sym[1] = not sym[1]; _update_ui(), true],
			["m_sym_z", "Symmetry Z " + ("off" if sym[2] else "on"), "", "Edits mirror across Z.", func(): sym[2] = not sym[2]; _update_ui(), true],
			["m_symmetrize", "Symmetrize +X to -X", "", "Copies the + side onto the - side.", func(): symmetrize(_sym_axis(), true), true],
			["m_symmetrize_back", "Symmetrize -X to +X", "", "Copies the - side onto the + side.", func(): symmetrize(_sym_axis(), false), true],
			["m_symmetrize_topo", "Symmetrize topology", "Ctrl+Shift+M", "Rebuilds the other side as the mirror of the side you've changed: its faces and points too, welded at the seam.", func(): symmetrize_topology(_sym_axis(), true, true), true],
		])
	groups.append([
		["m_move_smart", "Smart axis move", "", "Dragging the selection moves it along its own axis the drag goes.", func(): set_move_mode("smart"), move_mode != "smart"],
		["m_move_persp", "Perspective move", "", "Dragging the selection moves it over the plane you're looking at, snapping to its axes.", func(): set_move_mode("perspective"), move_mode != "perspective"],
		["m_gizmo", "Hide the gizmo" if gizmo_on else "Show the gizmo", "Ctrl+G", "The move / turn / scale handles on the selection.", toggle_gizmo, true],
		["m_frame", "Frame selected", "F", "Centres the view on the selection.", frame_selected, true],
		["m_frame_all", "Frame all", "Home", "The whole model in view.", frame_all, true],
		["m_front", "Front view", "Numpad 1", "From the front.", func(): view.set_view("front"), true],
		["m_side", "Side view", "Numpad 3", "From the right side.", func(): view.set_view("side"), true],
		["m_top", "Top view", "Numpad 7", "From above.", func(): view.set_view("top"), true],
		["m_ortho", "Perspective / orthographic", "Numpad 5", "Flat or in perspective.", func(): view.ortho = not view.ortho; view.update_camera(), true],
	])
	# (undo, redo, save, open and the wireframe: on the toolbars, not in this menu)
	return groups


## One page of the right-click menu (`page`: "mesh" or "curve"): its groups of icon buttons, each its own
## icon, a thin line between groups.
func _menu_page(box: VBoxContainer, groups: Array, page := "mesh") -> void:
	# (one flowing row: the groups side by side, a thin line between)
	var row := HFlowContainer.new()
	row.custom_minimum_size.x = 10 * 40
	row.add_theme_constant_override("h_separation", 4)
	row.add_theme_constant_override("v_separation", 4)
	box.add_child(row)
	# (only what can be done now: tools that can't run here aren't shown at all)
	var live := []
	for g in groups:
		var on: Array = (g as Array).filter(func(it): return bool(it[5]))
		if not on.is_empty():
			live.append(on)
	groups = live
	for gi in groups.size():
		if gi > 0 and not (groups[gi] as Array).is_empty():
			var vs := VSeparator.new()
			vs.custom_minimum_size = Vector2(6, 36)
			row.add_child(vs)
		for it in groups[gi]:
			var cb: Callable = it[4]
			var b := Button.new()
			b.icon = EditorIcons.get_icon(it[0])
			IconAnim.attach(b, it[0])
			b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			b.custom_minimum_size = Vector2(36, 36)
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = EditorIcons.tip(it[1], it[2], it[3])
			b.disabled = not it[5]
			b.name = "Menu_" + str(it[1]).validate_node_name()
			b.pressed.connect(func():
				_menu_close(_menu)   # (folds shut as the tool starts)
				cb.call())
			row.add_child(b)


## The menu kept inside the window, by its real size.
func _fit_menu() -> void:
	if _menu == null or not is_instance_valid(_menu) or not _menu.visible:
		return
	_menu.reset_size()
	var win := get_viewport().get_visible_rect().size
	var p := Vector2(_menu.position)
	var sz := Vector2(_menu.size)
	p.x = clampf(p.x, 4.0, maxf(4.0, win.x - sz.x - 4.0))
	p.y = clampf(p.y, 4.0, maxf(4.0, win.y - sz.y - 4.0))
	_menu.position = Vector2i(p)


func _toggle_mirror(a: int) -> void:
	var mm: Dictionary = part.get_meta("mesh_mirror", {}).duplicate(true)
	var axes: Array = mm.get("axes", []).duplicate()
	if a in axes:
		axes.erase(a)
	else:
		axes.append(a)
	if axes.is_empty():
		set_mirror(part, {})
	else:
		mm["axes"] = axes
		if not mm.has("merge"):
			mm["merge"] = 0.001
		if not mm.has("clip"):
			mm["clip"] = true
		set_mirror(part, mm)
	_show_part()


func _invert_selection() -> void:
	if em == null:
		return
	if sel_kind == 3:
		for arr: PackedByteArray in [sel_pa, sel_e, sel_t]:
			for i in arr.size():
				arr[i] = 0 if arr[i] else 1
		_derive_sel()
		_overlays()
		return
	var arr: PackedByteArray = [sel_p, sel_e, sel_t][sel_kind]
	for i in arr.size():
		arr[i] = 0 if arr[i] else 1
	match sel_kind:
		0: sel_p = arr
		1: sel_e = arr
		2: sel_t = arr
	_derive_sel()
	_overlays()


func set_radius(r: float) -> void:
	prop_radius = clampf(r, 0.001, 100.0)
	_radius.set_value_no_signal(prop_radius)
	if not xf.is_empty() and mode == "edit":
		# the pull's reach changed: start again from where the points were
		em.restore(xf["snap"])
		_xf_influence(xf)
		_xf_update()


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or not is_visible_in_tree():
		return
	var f := get_viewport().gui_get_focus_owner()
	if f is LineEdit or f is TextEdit:
		return
	if k.echo and not k.keycode in [KEY_Z, KEY_Y]:
		return
	if mesh_ops.key(k):   # (an inset's typed width, the loop cut's Esc)
		get_viewport().set_input_as_handled()
		return
	if curve_tools.key(k):   # (the sketch tools; typed sizes; the selected curves' Delete / Shift+D)
		get_viewport().set_input_as_handled()
		return
	var handled := true
	var kc := k.keycode
	if k.ctrl_pressed:
		match kc:
			KEY_Z:
				if not knife.is_empty():
					knife_back()
				elif k.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y: redo()
			KEY_X:
				if em:
					dissolve_selected()
				else:
					handled = false
			KEY_S:
				if k.shift_pressed:
					save_as()
				else:
					save()
			KEY_N: _ask_unsaved(func(): new_model())
			KEY_G: toggle_gizmo()
			KEY_R:
				if em:
					mesh_ops.begin_loopcut()
				else:
					handled = false
			KEY_M:
				if k.shift_pressed and em:
					symmetrize_topology(_sym_axis(), true, true)
				else:
					set_maximized(not maximized)
			KEY_BRACKETLEFT: set_left_panel(not left_shown)
			KEY_BRACKETRIGHT: set_right_panel(not right_shown)
			KEY_T: toggle_tpose()
			KEY_W:
				if k.shift_pressed:
					toggle_wire()
				else:
					set_weapons(not weapons_shown)
			KEY_O: _import()
			KEY_KP_1: view.set_view("front", true)
			KEY_KP_3: view.set_view("side", true)
			KEY_KP_7: view.set_view("top", true)
			_: handled = false
	elif not knife.is_empty():
		match kc:
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: knife_confirm()
			KEY_ESCAPE:
				knife_cancel()
				_say("Knife stopped.")
			KEY_BACKSPACE: knife_back()
			KEY_K: begin_knife(k.shift_pressed)   # (again: start over)
			_: handled = false
	elif not xf.is_empty():
		match kc:
			KEY_X, KEY_Y, KEY_Z:
				var a := kc - KEY_X
				xf["axis"] = -1 if xf["axis"] == a else a
				xf["dir"] = Vector3.ZERO
				_xf_update()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: confirm_transform()
			KEY_ESCAPE: _cancel_xf()
			KEY_PAGEUP: set_radius(prop_radius * 1.15)
			KEY_PAGEDOWN: set_radius(prop_radius / 1.15)
			KEY_0, KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
				if xf.get("kind", "") in ["SPH", "FLT"]:
					xf["sph_f" if xf["kind"] == "SPH" else "flt_f"] = 1.0 if kc == KEY_0 else float(kc - KEY_0) / 10.0   # (1-9: 10-90%, 0: all the way)
					_xf_update()
				else:
					handled = false
			_: handled = false
	else:
		match kc:
			KEY_TAB: pass   # (no mesh editing: ECurve objects are edited by their solids, faces, edges and vertices)
			KEY_F2:
				if mode == "object":
					curve_tools.rename_selected()
				else:
					handled = false
			KEY_K:
				if mode == "edit":
					begin_knife(k.shift_pressed)
				else:
					handled = false
			KEY_G: begin_transform("G")
			KEY_R: begin_transform("R")
			KEY_S:
				if k.shift_pressed and k.alt_pressed:
					spherize()
				else:
					begin_transform("S")
			KEY_1, KEY_2, KEY_3, KEY_4:
				if mode == "edit":
					set_kind(kc - KEY_1)
				else:
					handled = false
			KEY_L:
				if em:
					select_material_island()
			KEY_E:
				if em:
					extrude()
			KEY_M:
				if em and k.alt_pressed:
					mesh_ops.merge_by_distance()
				elif em:
					merge_selected()
			KEY_I:
				if em:
					mesh_ops.begin_inset()
				else:
					handled = false
			KEY_A:
				if em:
					select_all(not k.alt_pressed)
				elif k.shift_pressed:
					add_primitive("box")
			KEY_D:
				if k.shift_pressed and mode == "object":
					duplicate_part()
				elif k.shift_pressed and em:
					mesh_ops.duplicate_selection()
				else:
					handled = false
			KEY_X, KEY_DELETE:
				if em:
					delete_selected()
				else:
					delete_part()
			KEY_O:
				if k.shift_pressed:
					_falloff.select((EditMesh.FALLOFFS.find(prop_falloff) + 1) % EditMesh.FALLOFFS.size())
					prop_falloff = EditMesh.FALLOFFS[_falloff.selected]
					_say("Falloff: " + prop_falloff)
				elif k.alt_pressed:
					_connected.button_pressed = not _connected.button_pressed
				else:
					_prop_btn.button_pressed = not _prop_btn.button_pressed
					_say("Proportional editing " + ("on" if prop_on else "off"))
			KEY_KP_1: view.set_view("front")
			KEY_KP_3: view.set_view("side")
			KEY_KP_7: view.set_view("top")
			KEY_KP_5:
				view.ortho = not view.ortho
				view.update_camera()
			KEY_F, KEY_KP_PERIOD:
				if kc == KEY_F and k.shift_pressed and k.alt_pressed:
					deform.begin_flatten()
				else:
					frame_selected()
			KEY_V:
				if em:
					deform.begin_curve()
				else:
					handled = false
			KEY_HOME: frame_all()
			KEY_F1: EditorDocs.open(self, "mesh", EditorDocs.FILE)
			KEY_ESCAPE:
				if _drag == "box":
					_drag = ""
					view.box = Rect2()
					view.queue_redraw()
				elif not embedded:
					get_viewport().set_input_as_handled()
					TalosNav.go(get_tree(), "menu", guard)
					return
				else:
					handled = false
			_: handled = false
	if handled:
		get_viewport().set_input_as_handled()


# --- the T-pose and the weapons ----------------------------------------------------

const TPose := preload("res://scripts/editor/mesh/tpose.gd")
var weapons_shown := true
var _tpose_task := -1
var _tpose_out: Array = []


## The model's characters laid out in a T-pose for editing (arms out, the weapon beside
## them) - or back in their own pose. On a worker; undoable. Saving always writes them
## in their own pose.
func toggle_tpose() -> void:
	if model == null or _tpose_task >= 0:
		return
	if mode == "edit":
		_leave_edit(true)
	var jobs := []   # [part, mesh, mats, back]
	var any_on := false
	for p: MeshInstance3D in parts():
		if p.has_meta("tpose") or p.has_meta("tpose_xf"):
			any_on = true
	var all := parts()
	for p: MeshInstance3D in parts():
		if p.has_meta("weapons_part"):
			all.append(p.get_meta("weapons_part"))   # (hidden weapons turn with the body)
	for p: MeshInstance3D in all:
		if any_on and p.has_meta("tpose"):
			jobs.append([p, p.mesh, p.get_meta("tpose_mats"), true])
		elif not any_on and TPose.can(p):
			var sk := TPose.skeleton_of(p)
			jobs.append([p, p.mesh, TPose.matrices(p, sk, TPose.pose(sk)), false])
	var turned := _tpose_ecurves(any_on)
	if jobs.is_empty():
		if not turned:
			_say("No character here to T-pose (a solid skinned to a skeleton, or ECurve solids moving with bones).")
		return
	_say("Laying it out..." if not any_on else "Back in its own pose...")
	_tpose_out = []
	_tpose_task = WorkerThreadPool.add_task(func():
		var out := []
		for j in jobs:
			out.append(TPose.bake(j[1], j[2], j[3]))
		_tpose_out = [jobs, out], false, "ECurves editor: T-pose")


func _tpose_done() -> void:
	var jobs: Array = _tpose_out[0]
	var outs: Array = _tpose_out[1]
	var before := []
	var after := []
	for i in jobs.size():
		var p: MeshInstance3D = jobs[i][0]
		var back: bool = jobs[i][3]
		var m := TPose.mesh_from(outs[i])
		var mt := func(k: String): return p.get_meta(k) if p.has_meta(k) else null
		before.append([p, p.mesh, p.skin, p.skeleton, mt.call("tpose"), mt.call("tpose_mats"), mt.call("tpose_skin"), mt.call("tpose_skel")])
		if back:
			after.append([p, m, p.get_meta("tpose_skin"), p.get_meta("tpose_skel"), null, null, null, null])
		else:
			after.append([p, m, null, NodePath(""), true, jobs[i][2], p.skin, p.skeleton])
	var put := func(st: Array):
		for e in st:
			var p: MeshInstance3D = e[0]
			p.mesh = e[1]
			p.skin = e[2]
			p.skeleton = e[3]
			for k in 4:
				var key: String = ["tpose", "tpose_mats", "tpose_skin", "tpose_skel"][k]
				if e[4 + k] == null:
					p.remove_meta(key)
				else:
					p.set_meta(key, e[4 + k])

		_em_tm = null
		_place_ghosts()
		_update_ui()
		view.request()
	_do("T-pose", put.bind(after), put.bind(before))
	dirty = true
	var on: bool = not after.is_empty() and after[0][4] == true
	_say("T-pose: arms out, its weapon beside it - edit away; it's saved in its own pose." if on else "Back in its own pose.")
	if on:
		frame_all()


func is_tposed() -> bool:
	for p: MeshInstance3D in parts():
		if p.has_meta("tpose") or p.has_meta("tpose_xf"):
			return true
	return false


## ECurve solids laid out in the T-pose (or back, `back`): each turned whole by the bone it moves with
## (its recipe's "bone_name") - from that bone's rest to its T-pose - its edges with it, nothing reshaped.
## One undo step; saved in its own pose. Whether any was.
func _tpose_ecurves(back: bool) -> bool:
	var before := []
	var after := []
	for p: MeshInstance3D in parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		if back:
			if p.has_meta("tpose_xf"):
				before.append([p, p.transform, p.get_meta("tpose_xf")])
				after.append([p, p.get_meta("tpose_xf"), null])
			continue
		var bn := str(spec.get("bone_name", ""))
		if bn == "" or p.has_meta("tpose_xf"):
			continue
		var sk := _rig_of(p)
		if sk == null:
			continue
		var b := sk.find_bone(bn)
		if b < 0:
			b = sk.find_bone(bn.validate_node_name())   # (a model written before bone names were kept: "upper_L")
		if b < 0:
			for k in sk.get_bone_count():
				if sk.get_bone_name(k).validate_node_name() == bn.validate_node_name():
					b = k
					break
		if b < 0:
			continue
		if not sk.has_meta("tpose_g"):
			sk.set_meta("tpose_g", TPose.pose(sk))
		var g: Array = sk.get_meta("tpose_g")
		var delta: Transform3D = (g[b] as Transform3D) * sk.get_bone_global_rest(b).affine_inverse()
		var S: Transform3D = p.get_parent().global_transform.affine_inverse() * sk.global_transform if p.is_inside_tree() and sk.is_inside_tree() else Transform3D()
		before.append([p, p.transform, null])
		after.append([p, S * delta * S.affine_inverse() * p.transform, p.transform])
	if after.is_empty():
		return false
	var put := func(st: Array):
		for e in st:
			(e[0] as Node3D).transform = e[1]
			if e[2] == null:
				(e[0] as Node).remove_meta("tpose_xf")
			else:
				(e[0] as Node).set_meta("tpose_xf", e[2])
		curve_tools.refresh_solids()
		_update_ui()
		view.request()
	_do("T-pose", put.bind(after), put.bind(before))
	dirty = true
	_say("Back in its own pose." if back else "T-pose: arms out, its weapon beside it - edit away; it's saved in its own pose.")
	if not back:
		frame_all()
	return true


## The skeleton ECurve solid `p` moves with: its own, else one beside it in its collection (a dropped
## character's "Rig"), else the model's.
func _rig_of(p: MeshInstance3D) -> Skeleton3D:
	var own := p.get_node_or_null(p.skeleton) as Skeleton3D if p.skeleton != NodePath("") else null
	if own:
		return own
	var n: Node = p.get_parent()
	while n != null and n != model.get_parent():
		for c in n.get_children():
			if c is Skeleton3D:
				return c
		n = n.get_parent()
	var all := model.find_children("*", "Skeleton3D", true, false)
	return all[0] if not all.is_empty() else null


## The model's weapons shown or hidden: hidden, each part's weapon surfaces (by their
## materials: TPose.WEAPON_MATS) are taken out into a part of their own, hidden - not
## drawn, not edited, not picked - and put back when shown, and while saving (the file
## keeps them). Undoable.
func set_weapons(on: bool) -> void:
	if mode == "edit":
		_leave_edit(true)
	var before := []
	var after := []
	var made := []
	var wb := []   # (whole solids that are weapons - an ECurve object's rifle: [solid, shown])
	var wa := []
	for p: MeshInstance3D in parts():
		if p.has_meta("weapon_hidden") or (not p.has_meta("weapons_part") and _whole_weapon(p)):
			if on == p.has_meta("weapon_hidden"):
				wb.append([p, not on])
				wa.append([p, on])
			continue
		var w: MeshInstance3D = p.get_meta("weapons_part") if p.has_meta("weapons_part") else null
		if on and w:
			before.append([p, p.mesh, w, true])
			after.append([p, TPose.join(p.mesh, w.mesh), w, false])
		elif not on and not w:
			var sp := TPose.split_weapons(p)
			if sp[1] == null:
				continue
			var nw := MeshInstance3D.new()
			nw.name = str(p.name) + "_Weapons"
			nw.mesh = sp[1]
			nw.skin = p.skin
			nw.skeleton = p.skeleton
			nw.transform = p.transform
			nw.visible = false
			nw.set_meta("weapons_of", p)
			for k in ["tpose", "tpose_mats", "tpose_skin", "tpose_skel"]:
				if p.has_meta(k):
					nw.set_meta(k, p.get_meta(k))
			made.append(nw)
			before.append([p, p.mesh, nw, false])
			after.append([p, sp[0], nw, true])
	weapons_shown = on
	if after.is_empty() and wa.is_empty():
		_update_ui()
		_say("No weapons on this model." if not on else "Weapons shown.")
		return
	var put := func(st: Array, ws: Array):
		for e in ws:
			# (a weapon solid hidden whole: not drawn, not picked - still saved)
			(e[0] as Node3D).visible = e[1]
			if e[1]:
				(e[0] as Node).remove_meta("weapon_hidden")
			else:
				(e[0] as Node).set_meta("weapon_hidden", true)
		for e in st:
			var p: MeshInstance3D = e[0]
			var w: MeshInstance3D = e[2]
			p.mesh = e[1]
			if e[3]:
				if w.get_parent() == null:
					p.get_parent().add_child(w)
				p.set_meta("weapons_part", w)
			else:
				if w.get_parent():
					w.get_parent().remove_child(w)
				p.remove_meta("weapons_part")
		weapons_shown = (st.is_empty() or not st[0][3]) and (ws.is_empty() or bool(ws[0][1]))
		_em_tm = null
		_outlined = null
		_fill_parts()
		_update_ui()
		view.request()
	_do("Weapons shown" if on else "Weapons hidden", put.bind(after, wa), put.bind(before, wb), made)
	_say("Weapons shown." if on else "Weapons hidden - they're still there and still saved.")


## Whether solid `p` is all weapon (every surface a weapon's material: TPose.WEAPON_MATS) - an ECurve
## object's rifle or bow is a solid of its own.
func _whole_weapon(p: MeshInstance3D) -> bool:
	if p.mesh == null or p.mesh.get_surface_count() == 0:
		return false
	var ws := TPose.weapon_surfaces(p)
	if ws.size() == p.mesh.get_surface_count():
		return true
	# (an ECurve solid moving with a weapon's bone - the gun's grey parts)
	var bn := str((p.get_meta("curve_solid", {}) as Dictionary).get("bone_name", "")).to_lower()
	if bn in TPose.WEAPON_BONES:
		return true
	# (its material set on the part, not the mesh)
	var m := p.material_override if p.material_override else p.get_surface_override_material(0)
	return m != null and p.mesh.get_surface_count() == 1 and TPose.is_weapon_material(m.resource_name)


## What the view turns about: in edit mode the selected elements' middle (none selected:
## the view's own target).
func _orbit_pivot() -> Vector3:
	if _pivot_ms == _drag_started:
		return _pivot_cache   # (worked out once a drag)
	_pivot_ms = _drag_started
	_pivot_cache = Vector3.INF
	# (round the selection - the smallest thing picked first: mesh points in edit mode, a curve's point
	# last pressed, the picked curves, the selected solids)
	if mode == "edit" and em and part:
		var sel := selected_points()
		if not sel.is_empty():
			_pivot_cache = part.global_transform * em.centroid(sel)
			return _pivot_cache
	if curve_tools:
		var cp: Vector3 = curve_tools.selection_centre()
		if cp != Vector3.INF:
			_pivot_cache = cp
			return _pivot_cache
	var box := AABB()
	var first := true
	for p: MeshInstance3D in selected_parts():
		if p.mesh == null:
			continue
		var b := p.global_transform * p.mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if not first:
		_pivot_cache = box.get_center()
	return _pivot_cache


var _pivot_cache := Vector3.INF
var _pivot_ms := -1
var _drag_started := 0


# --- the gizmo -------------------------------------------------------------------

var _gizmo_drag := false
## The gizmo shown (off at first: Ctrl+G, or its toolbar button; remembered).
var gizmo_on := false
var _gizmo_btn: Button


func toggle_gizmo() -> void:
	gizmo_on = not gizmo_on
	if _gizmo_btn:
		_gizmo_btn.set_pressed_no_signal(gizmo_on)
	var c := ConfigFile.new()
	c.load(LAYOUT)
	c.set_value("mesh", "gizmo", gizmo_on)
	c.save(LAYOUT)
	_sync_gizmo()
	_say("Gizmo " + ("shown." if gizmo_on else "hidden (Ctrl+G shows it)."))


## The gizmo at the selection: the part (object mode) or the selected points' middle (edit
## mode); none while a transform runs, or with nothing selected.
func _sync_gizmo() -> void:
	if view == null:
		return
	var at := Vector3.INF
	if gizmo_on and (xf.is_empty() or _gizmo_drag):
		if mode == "object" and part and is_instance_valid(part) and part.is_inside_tree():
			at = part.global_position
		elif mode == "edit" and em and part:
			var sel := selected_points()
			if not sel.is_empty():
				at = part.global_transform * em.centroid(sel)
	if _gizmo_drag and not xf.is_empty():
		at = Vector3.INF   # (hidden while it's dragged: the transform's own hint shows)
	if not knife.is_empty():
		at = Vector3.INF   # (none while the knife draws)
	if at != Vector3.INF and not _hovering:
		var fb := sel_frame()
		if not fb.is_equal_approx(view.gizmo_basis):
			view.gizmo_basis = fb
			view.queue_redraw()
	if at != view.gizmo_at:
		view.gizmo_at = at
		view.queue_redraw()


# --- the selection's outline ----------------------------------------------------

var _outlined: MeshInstance3D


## The selected part outlined (amber; in edit mode fainter - its points and faces are the selection there).
func _outline_part() -> void:
	var want: MeshInstance3D = part if part and is_instance_valid(part) and part.is_inside_tree() else null
	if _outlined == want and (want == null or want.get_meta("outline_mode", "") == mode):
		_outline_others()
		return
	if _outlined and is_instance_valid(_outlined):
		SelectOutline.show(_outlined, false, Color.WHITE, false)
	_outlined = want
	if want:
		SelectOutline.show(want, true, Color(1.0, 0.42, 0.0, 1.0 if mode == "object" else 0.6), false)
		want.set_meta("outline_mode", mode)
	_outline_others()
	if view:
		view.request()


## The other selected parts outlined fainter (gold).
func _outline_others() -> void:
	var want: Array = selected_parts().filter(func(p): return p != part) if mode == "object" else []
	for p in _outlined_more:
		if is_instance_valid(p) and not p in want and p != part:
			SelectOutline.show(p, false, Color.WHITE, false)
	for p in want:
		if not p in _outlined_more:
			SelectOutline.show(p, true, Color(1.0, 0.75, 0.1, 0.9), false)
	_outlined_more = want


# --- undo ---------------------------------------------------------------------

## Does a change and records it (`nodes`: nodes it adds or removes - freed
## once no undo step can bring them back).
func _do(name: String, do_it: Callable, undo_it: Callable, nodes := []) -> void:
	do_it.call()
	_push(name, undo_it, do_it, nodes)


func _push(name: String, undo_it: Callable, redo_it: Callable, nodes := []) -> void:
	_undo.append({"name": name, "undo": undo_it, "redo": redo_it, "nodes": nodes})
	if _undo.size() > UNDO_MAX:
		_drop_entries([_undo.pop_front()])
	_drop_entries(_redo)
	_redo.clear()
	dirty = true
	_update_ui()


## Frees the nodes of dropped undo steps that aren't in the model.
func _drop_entries(entries: Array) -> void:
	for e in entries:
		for n in e.get("nodes", []):
			if is_instance_valid(n) and not n.is_inside_tree() and n.get_parent() == null:
				n.free()


func undo() -> void:
	if curve_tools:
		curve_tools._knife_step(true)   # (a knife cut still being finished: its step made first)
		curve_tools._settle_finish()   # (a drag let go still settling: its step made first)
	knife_cancel()
	if curve_tools.active():
		curve_tools.cancel_op()
		curve_tools.stop()
		return
	if not xf.is_empty():
		_cancel_xf()
		return
	var stack := _eundo if mode == "edit" else _undo
	if stack.is_empty():
		_say("Nothing to undo.")
		return
	var e: Dictionary = stack.pop_back()
	(e["undo"] as Callable).call()
	(_eredo if mode == "edit" else _redo).append(e)
	dirty = true
	_say("Undone: " + str(e["name"]))
	_update_ui()


func redo() -> void:
	if curve_tools:
		curve_tools._knife_step(true)   # (a knife cut still being finished: its step made first)
		curve_tools._settle_finish()   # (a drag let go still settling: its step made first)
	knife_cancel()
	var stack := _eredo if mode == "edit" else _redo
	if stack.is_empty():
		_say("Nothing to redo.")
		return
	var e: Dictionary = stack.pop_back()
	(e["redo"] as Callable).call()
	(_eundo if mode == "edit" else _undo).append(e)
	dirty = true
	_say("Redone: " + str(e["name"]))
	_update_ui()


# --- materials ------------------------------------------------------------------

func _show_material_list() -> void:
	var surf: OptionButton = _mat["surface"]
	surf.clear()
	if part:
		for i in part.mesh.get_surface_count():
			var m := part.mesh.surface_get_material(i)
			var nm := ""
			if part.mesh is ArrayMesh:
				nm = (part.mesh as ArrayMesh).surface_get_name(i)
			surf.add_item("%d: %s" % [i + 1, (m.resource_name if m and m.resource_name != "" else nm) if (m or nm != "") else "surface"])
	_show_material()


func _surface_index() -> int:
	return (_mat["surface"] as OptionButton).selected


func _show_material() -> void:
	mat_tools.show_surface(part, _surface_index())


## Gives surface `s` of part `p` material `mat` (undoable).
func set_surface_material(p: MeshInstance3D, s: int, mat: Material) -> void:
	if p == null or s < 0 or s >= p.mesh.get_surface_count():
		return
	var mesh: Mesh = p.mesh
	var old := mesh.surface_get_material(s)
	var put := func(m: Material):
		mesh.surface_set_material(s, m)
		if em and p == part and p.mesh == mesh:
			_em_surf_material(s, m)
		if p == part:
			_show_material_list()
			(_mat["surface"] as OptionButton).select(s)
			_show_material()
		view.request()
	_do("Material", put.bind(mat), put.bind(old))


func _em_surf_material(s: int, m: Material) -> void:
	var k := 0
	for es in em.surfs:
		if not es.idx.is_empty():
			if k == s:
				es.material = m
				return
			k += 1


## Changes one property of the selected surface's material (a BaseMaterial3D property name) -
## on every surface using it (the MATERIAL panel: mat_tools.set_value).
func _mat_set(prop: String, v: Variant) -> void:
	_show_material()
	var key := {"albedo_color": "color", "metallic": "metal", "roughness": "rough", "emission_energy_multiplier": "emit", "emission": "emission"}.get(prop, prop) as String
	if v is Color:
		var c: Color = v
		v = [c.r, c.g, c.b, c.a] if key == "color" else [c.r, c.g, c.b]
	mat_tools.set_value(key, v)


# --- files -------------------------------------------------------------------

## A character's materials as the game uses them: the game merges a character into one surface and
## takes each material's colour - and, edited here, its metal, roughness and glow - from its
## model.json table by name; so the materials edited (or newly given) here are written there (the
## game's copy, or the mod's), and the running game's cache of that character forgotten.
func _write_material_table(res_path: String) -> void:
	var json_path := res_path.get_base_dir() + "/model.json"
	var src := _read_source(res_path, "model.json")
	var d = JSON.parse_string(FileAccess.get_file_as_string(src)) if FileAccess.file_exists(src) else null
	if not d is Dictionary:
		return
	var table: Dictionary = d.get("materials", {})
	var n := 0
	var seen := {}
	for p: MeshInstance3D in parts():
		if p.mesh == null:
			continue
		for i in p.mesh.get_surface_count():
			var m := p.get_surface_override_material(i)
			if m == null:
				m = p.mesh.surface_get_material(i)
			var bm := m as BaseMaterial3D
			if bm == null or bm.resource_name == "" or seen.has(bm.resource_name):
				continue
			seen[bm.resource_name] = true
			if not bm.has_meta("mesh_editor_own") and table.has(bm.resource_name):
				continue   # (not edited, already known: as it was)
			var row: Dictionary = table.get(bm.resource_name, {}).duplicate()
			var c := bm.albedo_color
			row["color"] = [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001)]
			row["metal"] = snappedf(bm.metallic, 0.01)
			row["rough"] = snappedf(bm.roughness, 0.01)
			row["emit"] = snappedf(bm.emission_energy_multiplier if bm.emission_enabled else 0.0, 0.01)
			if not row.has("kind"):
				row["kind"] = "toon"
			table[bm.resource_name] = row
			n += 1
	if n == 0:
		return
	d["materials"] = table
	var f := FileAccess.open(_write_target(res_path, "model.json"), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	var id := res_path.get_file().get_basename()
	CosmosModels.forget(id)
	_say("Saved - and %d material%s into %s (the game's look of it)." % [n, "" if n == 1 else "s", json_path.get_file()])


# --- overrides: saving never writes over the original ----------------------------------

const ModelOverride := preload("res://scripts/world/models/model_override.gd")


## Where saving `model_path`'s file `name` (the model's own if none) writes: in a mod, the mod's copy
## (it overrides the game's); in the game, the open variant of its override (art/overrides/; a new
## variant if the original is open) - the original kept as it was. A model new to the game is
## written where it's saved (there's nothing to override).
func _write_target(model_path: String, name := "") -> String:
	var file := model_path.get_base_dir().path_join(name) if name != "" else model_path
	if EditTarget.is_mod():
		return EditTarget.write_path(file)
	if name == "" and not FileAccess.file_exists(model_path) and not ResourceLoader.exists(model_path):
		return model_path
	if variant <= 0 or not variant in ModelOverride.variants(model_path):
		variant = ModelOverride.add(model_path)
	return ModelOverride.file_of(model_path, variant, name)


## What `model_path`'s file `name` reads as: the mod's copy, else the open variant's, else the original.
func _read_source(model_path: String, name := "") -> String:
	var file := model_path.get_base_dir().path_join(name) if name != "" else model_path
	if EditTarget.is_mod():
		return EditTarget.read_path(file) if EditTarget.overridden(file) else file
	return ModelOverride.read(model_path, name, variant)


## The model file to open for variant `v`.
func _model_source(res_path: String, v: int) -> String:
	if EditTarget.is_mod():
		return EditTarget.read_path(res_path) if EditTarget.overridden(res_path) else res_path
	return ModelOverride.read(res_path, "", v)


## The variant opening `res_path` means: `v`, or (-1) the active one - none in a mod.
func _variant_to_open(res_path: String, v: int) -> int:
	if EditTarget.is_mod() or res_path == "":
		return 0
	return ModelOverride.active(res_path) if v < 0 else v


func _refresh_variants(res_path := path) -> void:
	_variants = [] if EditTarget.is_mod() or res_path == "" else ModelOverride.variants(res_path)
	_fill_variants()
	fill_variant_browser(res_path)


## The variants' list: Original, then each variant (the latest marked active), the open one picked.
func _fill_variants() -> void:
	if _variant_opt == null:
		return
	_variant_opt.clear()
	_variant_opt.add_item("Original", 0)
	for n in _variants:
		var t := ModelOverride.saved_at(path, n)
		_variant_opt.add_item("Variant %d%s" % [n, "  · active" if n == _variants[-1] else ""], n)
		_variant_opt.set_item_tooltip(_variant_opt.item_count - 1, ("Saved %s" % Time.get_datetime_string_from_unix_time(t, true)) if t > 0 else "Not saved yet: the original's mesh")
	_variant_opt.select(maxi(0, _variant_opt.get_item_index(variant)))
	_variant_state()


func _variant_state() -> void:
	if _variant_opt == null:
		return
	var game := not EditTarget.is_mod() and path != "" and EditTarget.writable()
	_variant_opt.disabled = not game
	(_variant_btns[0] as Button).disabled = not game
	(_variant_btns[1] as Button).disabled = not game or model == null
	(_variant_btns[2] as Button).disabled = not game or variant <= 0


## The running game's copies of `res_path` forgotten: it draws the active variant (or the original).
func _forget_game(res_path: String) -> void:
	ModelOverride.forget(res_path)
	if MeshIO.is_character(res_path):
		var id := res_path.get_file().get_basename()
		Stage3D._scenes.erase(id)
		CosmosModels.forget(id)


## Opens variant `n` of the open model (0 - the original).
func open_variant(n: int) -> void:
	if n == variant or path == "":
		_fill_variants()
		return
	_ask_unsaved(func(): _open(path, n))
	_fill_variants.call_deferred()   # (kept on the open one till the other is in)


## A new variant starting from the original: the latest, so the game uses it.
func add_variant() -> void:
	if path == "" or EditTarget.is_mod():
		return
	_ask_unsaved(func():
		var n := ModelOverride.add(path)
		_forget_game(path)
		dirty = false
		open_now(path, n)
		_fill_files()
		_update_ui()
		_say("Variant %d of %s: from the original - the active one now. Save to keep your edits in it." % [n, path.get_file()]))


## The open variant - unsaved edits and all - copied as a new variant (the latest: the game uses it).
func duplicate_variant() -> void:
	if path == "" or model == null or EditTarget.is_mod():
		return
	var from := variant
	variant = ModelOverride.add(path, from)
	if write_to(path) == OK:
		_say("Variant %d: a copy of %s - the active one now." % [variant, "the original" if from <= 0 else "variant %d" % from])


## The open variant deleted (asks first); the active one (or the original) opened.
func erase_variant(ask := true) -> void:
	if path == "" or variant <= 0 or EditTarget.is_mod():
		return
	var go := func():
		var gone := variant
		ModelOverride.erase(path, gone)
		_forget_game(path)
		dirty = false
		open_now(path)
		_fill_files()
		_update_ui()
		_say("Variant %d erased - %s." % [gone, ("variant %d is active" % variant) if variant > 0 else "the game uses the original"])
	if ask:
		UI.confirm(self, "ERASE THE VARIANT", "Delete variant %d of %s?%s" % [variant, path.get_file(), "\nIt's the active one: the game goes back to %s." % (("variant %d" % _variants[-2]) if _variants.size() > 1 else "the original") if variant == _variants.back() else ""], go, "Erase", "Keep")
	else:
		go.call()


## The open model has an override (or, in a mod, the mod's copy).
func has_override() -> bool:
	if path == "":
		return false
	return EditTarget.overridden(path) if EditTarget.is_mod() else ModelOverride.has(path)


## Revert to the original: every variant of the override (in a mod, the mod's copies) deleted, the
## original opened again, the running game's copies of it forgotten - it draws the original again.
func revert_to_original(ask := true) -> void:
	if not has_override():
		_say("This model has no override - it's the original.")
		return
	var many := ModelOverride.variants(path).size() if not EditTarget.is_mod() else 1
	var go := func():
		if EditTarget.is_mod():
			for p in [path, path.get_base_dir() + "/model.json"]:
				if FileAccess.file_exists(EditTarget.write_path(p)) and (p == path or MeshIO.is_character(path)):
					DirAccess.remove_absolute(EditTarget.write_path(p))
		else:
			for n in ModelOverride.variants(path):
				ModelOverride.erase(path, n)
		_forget_game(path)
		dirty = false
		var was := path
		open_now(was, 0)
		_fill_files()
		_update_ui()
		_say("Back to the original %s (the override deleted)." % was.get_file())
	if ask:
		UI.confirm(self, "REVERT TO THE ORIGINAL", "Delete your saved changes to %s%s and go back to the original?" % [path.get_file(), "" if many <= 1 else " - all %d variants -" % many], go, "Revert", "Keep")
	else:
		go.call()


func _start_scan() -> void:
	if _scan_task >= 0:
		return
	var root := EditTarget.root() if EditTarget.is_mod() else ""
	_scan_out = []
	_scan_task = WorkerThreadPool.add_task(func(): _scan_out = [MeshIO.scan(root)], false, "ECurves editor: scan")


## The models list as "icons" (a picture of each, its name under it) or "details" (paths).
func set_list_view(v: String) -> void:
	list_view = v
	for k in _view_btns:
		(_view_btns[k] as Button).set_pressed_no_signal(k == v)
	if v == "icons":
		_files.icon_mode = ItemList.ICON_MODE_TOP
		_files.max_columns = 0
		_files.fixed_icon_size = Vector2i(72, 72)
		_files.fixed_column_width = 84
		_files.same_column_width = true
	else:
		_files.icon_mode = ItemList.ICON_MODE_LEFT
		_files.max_columns = 1
		_files.fixed_icon_size = Vector2i(28, 28)
		_files.fixed_column_width = 0
		_files.same_column_width = false
	var c := ConfigFile.new()
	c.load(LAYOUT)
	c.set_value("mesh", "list_view", v)
	c.save(LAYOUT)
	_fill_files()


var list_view := "icons"
var _view_btns := {}
var _thumbs: Node


func _thumb_made(path: String, tex: Texture2D) -> void:
	for i in _files.item_count:
		if str(_files.get_item_metadata(i)) == path:
			_files.set_item_icon(i, tex)
			return


func _fill_files() -> void:
	if _thumbs != null and not _thumbs.has_meta("size"):
		# (made before its pictures were sharp on a big screen: made again)
		_thumbs.queue_free()
		_thumbs.name = "ThumbsOld"
		_thumbs = null
	if _thumbs == null:
		_thumbs = preload("res://scripts/editor/mesh/mesh_thumbs.gd").new()
		_thumbs.set_meta("size", 160)   # (shown 72 px - on a 4K screen 144 of its pixels: never stretched)
		_thumbs.name = "Thumbs"
		add_child(_thumbs)
		_thumbs.made.connect(_thumb_made)
		if _files.get_node_or_null("TurntableHover") == null:
			TurntableHover.attach(_files, func(meta): return _thumbs.frames(str(meta), EditTarget.read_path(str(meta))) if _thumbs else [])
	_thumbs.clear_queue()
	_files.clear()
	var words := _filter.text.to_lower().split(" ", false)
	_model_cats_bar()
	var cat := str(get_meta("model_cat", "all"))
	for p in _all_files:
		var ok := cat == "all" or model_category(p) == cat
		for w in words:
			if not p.to_lower().contains(w):
				ok = false
		if not ok:
			continue
		var label := p.get_file().get_basename() if list_view == "icons" else p.trim_prefix("res://")
		var file := EditTarget.read_path(p)
		var tex: Texture2D = _thumbs.get_thumb(p, file)
		if tex == null:
			_thumbs.ask(p, file)
		var i := _files.add_item(label, tex if tex else EditorIcons.get_icon("mesh"))
		_files.set_item_metadata(i, p)
		if MeshIO.is_character(p):
			_files.set_item_custom_fg_color(i, Color(1.0, 0.85, 0.55))
		if EditTarget.overridden(p) or (not EditTarget.is_mod() and ModelOverride.has(p)):
			_files.set_item_custom_fg_color(i, Color(0.55, 1.0, 0.6))   # (edited: an override of it is used)
		_files.set_item_tooltip(i, EditorIcons.tip(p.get_file().get_basename().capitalize(), "double-click", p + ("\nA character made by the Blender pipeline." if MeshIO.is_character(p) else "") + ("\nYour mod has its own copy." if EditTarget.overridden(p) else "") + ("\nEdited: your version is the one the game uses." if not EditTarget.is_mod() and ModelOverride.has(p) else "")))


## Saves the model as glb at its path (Save as, if it has none), then `then`.
func save(then := Callable()) -> void:
	if model == null:
		return
	if curve_tools:
		curve_tools._knife_step(true)   # (a knife cut still being finished: saved finished)
		curve_tools._settle_finish()   # (a drag let go still settling: saved settled)
	if not EditTarget.writable():
		_say("Saving isn't possible here (an exported game): make a mod and edit it in the Mod Editor.")
		return
	if mat_tools.lib.dirty or not mat_tools.lib.pending.is_empty():
		if mat_tools.save_library() == OK and parts().is_empty():
			dirty = false
			_update_ui()
			_say("Saved the material library to %s." % EditTarget.label())
			return
	if path == "" or not path.get_extension().to_lower() in ["glb", "gltf"]:
		save_as(then)
		return
	var err := write_to(path)
	if err == OK:
		if then.is_valid():
			then.call()


## Writes the model to `res_path` (through EditTarget) - its mirror modifiers
## applied; dirty cleared. The error code.
func write_to(res_path: String) -> int:
	if res_path != path:
		variant = 0   # (saved as another model: its own override)
	var file := _write_target(res_path)
	SelectOutline.show(_outlined, false, Color.WHITE, false)   # (not saved with it)
	_outlined = null
	for p in _outlined_more:
		if is_instance_valid(p):
			SelectOutline.show(p, false, Color.WHITE, false)
	_outlined_more = []
	curve_tools.rebase_edges()   # (baked solids: their edges as they are now - opened again as saved)
	for p: MeshInstance3D in parts():   # (a part's shape recipe kept in the glb's extras)
		var ex: Dictionary = p.get_meta("extras", {}).duplicate()
		if p.has_meta("mesh_shape"):
			ex["atrapos_shape"] = p.get_meta("mesh_shape")
		else:
			ex.erase("atrapos_shape")
		if p.has_meta("curve_solid"):   # (a solid made from curves: its recipe, made again from them when opened)
			ex["atrapos_curves"] = p.get_meta("curve_solid")
		else:
			ex.erase("atrapos_curves")
		if ex.is_empty():
			p.remove_meta("extras")
		else:
			p.set_meta("extras", ex)
	# Each part written as the model is: its hidden weapons put back in, a T-posed one in its
	# own pose (its skin back) - and all as it was again after.
	var saved := []
	for p: MeshInstance3D in parts():
		var w: MeshInstance3D = p.get_meta("weapons_part") if p.has_meta("weapons_part") else null
		if w == null and not p.has_meta("tpose"):
			continue
		saved.append([p, p.mesh, p.skin, p.skeleton, w])
		var m: ArrayMesh = p.mesh
		if w:
			m = TPose.join(m, w.mesh)
			if w.get_parent():
				w.get_parent().remove_child(w)
		if p.has_meta("tpose"):
			m = TPose.mesh_from(TPose.bake(m, p.get_meta("tpose_mats"), true))
			p.skin = p.get_meta("tpose_skin")
			p.skeleton = p.get_meta("tpose_skel")
		p.mesh = m
	var swapped := []
	for p: MeshInstance3D in parts():
		if p.has_meta("mesh_mirror"):
			swapped.append([p, p.mesh])
			p.mesh = mirrored_mesh(p)
	var boned := _apply_bone_links()   # (ECurve solids written skinned to the bones they're associated with)
	var unposed := []
	for p: MeshInstance3D in parts():
		if p.has_meta("tpose_xf"):
			unposed.append([p, p.transform])
			p.transform = p.get_meta("tpose_xf")   # (written in its own pose)
	var unhid := []
	for p: MeshInstance3D in parts():
		if p.has_meta("weapon_hidden"):
			p.visible = true   # (a hidden weapon solid written as it is in the game: shown)
			unhid.append(p)
	var err := MeshIO.write(model, file)
	for p in unhid:
		p.visible = false
	for e in unposed:
		e[0].transform = e[1]
	for b in boned:
		_set_bind_state(b[0], b[1])
	if err == OK:
		_forget_game(res_path)
		curve_tools.save_beside(file)   # (the model's curves: <file>.curves.json beside it)
	if err == OK and MeshIO.is_character(res_path):
		_write_material_table(res_path)
	if err == OK:
		mat_tools.save_library()
	for s in swapped:
		s[0].mesh = s[1]
	for e in saved:
		e[0].mesh = e[1]
		e[0].skin = e[2]
		e[0].skeleton = e[3]
		if e[4] and (e[4] as Node).get_parent() == null:
			(e[0] as Node).get_parent().add_child(e[4])
	if err != OK:
		_say("Couldn't save %s (%s)." % [file, error_string(err)])
		return err
	path = res_path
	dirty = false
	_refresh_variants()
	_update_ui()
	_say("Saved %s to %s%s." % [res_path, EditTarget.label(), "" if EditTarget.is_mod() or variant <= 0 else " as variant %d%s" % [variant, " (active: the game uses it)" if variant == _variants.back() else " (not the latest: the game uses variant %d)" % _variants.back()]])
	_start_scan()
	return OK


## Asks for a res:// path to save under.
func save_as(then := Callable()) -> void:
	if model == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var box := UI.modal(root, ACCENT, Vector2(620, 0))
	box.add_child(UI.label("Save as", 24, NeonTheme.HEAD))
	box.add_child(UI.note("A res:// path ending in .glb - saved into %s." % EditTarget.label(), 15, 560))
	var le := LineEdit.new()
	le.text = path if path.get_extension() in ["glb", "gltf"] else ("res://models/%s.glb" % str(model.name).to_snake_case() if path == "" else path.get_basename() + ".glb")
	le.add_theme_font_size_override("font_size", 16)
	box.add_child(le)
	var err_l := UI.label("", 14, Color(1.0, 0.45, 0.4))
	box.add_child(err_l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var go := func():
		var p := le.text.strip_edges()
		if not p.begins_with("res://"):
			p = "res://" + p.trim_prefix("/")
		if not p.get_extension().to_lower() in ["glb", "gltf"]:
			p += ".glb"
		if p.begins_with("res://.godot") or p.begins_with("res://external") or p.contains(".."):
			err_l.text = "Not there: pick a folder of the game (art/, models/...)."
			return
		layer.queue_free()
		path = p
		save(then)
	le.text_submitted.connect(func(_t): go.call())
	row.add_child(UI.button("Cancel", layer.queue_free, 16))
	row.add_child(UI.button("Save", go, 16))
	le.grab_focus.call_deferred()
	le.caret_column = le.text.length()


func _import() -> void:
	var fd := FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.glb, *.gltf, *.obj ; 3D models"])
	fd.title = "Import a model"
	fd.use_native_dialog = true
	add_child(fd)
	fd.file_selected.connect(func(f: String):
		fd.queue_free()
		_ask_unsaved(func():
			var n := MeshIO.read(f)
			if n == null:
				_say("Couldn't read %s." % f)
				return
			_set_model(n, "")
			dirty = true
			_update_ui()
			_say("Imported %s - Save as puts it into %s." % [f.get_file(), EditTarget.label()])))
	fd.canceled.connect(fd.queue_free)
	fd.popup_centered_ratio(0.6)


## Asks about unsaved changes (save / discard / stay), then `next`.
func guard(next: Callable) -> void:
	if not dirty:
		next.call()
		return
	UI.choice(self, "Unsaved changes", "The ECurves editor has unsaved changes%s. Save them first?" % (" to " + path if path != "" else ""), [
		["Stay", Callable()],
		["Discard", func(): dirty = false; next.call()],
		["Save", func(): save(next)],
	])


func _ask_unsaved(next: Callable) -> void:
	guard(next)


# --- status -------------------------------------------------------------------

func _say(t: String) -> void:
	if _note:
		_note.text = t + "    ·    saving to " + EditTarget.label()


## The model's stats in the view's corner: object mode - the model, its parts, points and
## triangles, the selected part's; edit mode - the part's points, edges, faces, triangles and
## what's selected of each.
func show_stats() -> void:
	if view == null:
		return
	var lines := PackedStringArray()
	if mode == "edit" and em and part:
		var sp := 0
		for b in sel_p:
			sp += b
		var se := 0
		for b in sel_e:
			se += b
		var faces := {}
		for t in mini(sel_t.size(), em.tri_count()):
			if sel_t[t]:
				faces[em.tri_face[t]] = true
		lines.append(str(part.name) + "  (edit)")
		lines.append("Points  %d   selected %d" % [em.points.size(), sp])
		lines.append("Edges  %d   selected %d" % [em.edge_count(), se])
		lines.append("Faces  %d   selected %d" % [em.poly_count(), faces.size()])
		lines.append("Triangles  %d" % em.tri_count())
	elif model:
		var ps := parts()
		var nv := 0
		var nt := 0
		var pv := 0
		var pt := 0
		for p: MeshInstance3D in ps:
			var v := 0
			var t := 0
			if p.mesh:
				for i in p.mesh.get_surface_count():
					v += p.mesh.surface_get_array_len(i)
					var ix: int = p.mesh.surface_get_array_index_len(i)
					t += (ix if ix > 0 else p.mesh.surface_get_array_len(i)) / 3
			nv += v
			nt += t
			if p == part:
				pv = v
				pt = t
		lines.append((path.get_file() if path != "" else "New model") + "   %d solid%s" % [ps.size(), "" if ps.size() == 1 else "s"])
		lines.append("Vertices  %d   Triangles  %d" % [nv, nt])
		if part:
			lines.append("%s:  %d vertices, %d triangles" % [part.name, pv, pt])
	view.stats = "\n".join(lines)
	view.queue_redraw()


func _update_ui() -> void:
	show_stats()
	update_side_panel()
	var pv: Button = _toolbar.get_node_or_null("PreviewInGame") if _toolbar else null
	if pv:
		pv.disabled = model == null
	if curve_tools:
		curve_tools._refresh_panel()
	_outline_part()
	if shape_tools and shape_tools.panel:
		shape_tools.refresh()
	if mat_tools:
		mat_tools.refresh_model()
	_sync_gizmo()
	if _mode_btn == null:
		return
	_mode_btn.icon = EditorIcons.get_icon("m_edit" if mode == "edit" else "m_object")
	_mode_btn.set_pressed_no_signal(mode == "edit")
	for i in 3:
		(_kind_btns[i] as Button).disabled = mode != "edit"
		(_kind_btns[i] as Button).set_pressed_no_signal(mode == "edit" and sel_kind == i)
	if _auto_btn and is_instance_valid(_auto_btn):
		_auto_btn.disabled = mode != "edit"
		_auto_btn.set_pressed_no_signal(mode == "edit" and sel_kind == 3)
	for a in 3:
		(_sym_btns[a] as Button).set_pressed_no_signal(sym[a])
	_save_btn.disabled = not EditTarget.writable()
	if _revert_btn:
		_revert_btn.disabled = not has_override()
	_variant_state()
	if _tpose_btn:
		_tpose_btn.set_pressed_no_signal(is_tposed())
		_weapons_btn.set_pressed_no_signal(weapons_shown)
	_edit_box.modulate.a = 1.0 if mode == "edit" else 0.6


# --- several parts selected; the shapes tab; booleans ------------------------------------

var _tree_active: MeshInstance3D
var _tree_due := false


## The selected parts still in the model (in the order picked; the active one last).
func selected_parts() -> Array:
	var out := []
	for p in sel_parts:
		if is_instance_valid(p) and p.is_inside_tree() and model and model.is_ancestor_of(p):
			out.append(p)
	if part and is_instance_valid(part) and part.is_inside_tree() and not part in out:
		out.append(part)
	return out


## The parts list's selection (several, with Ctrl / Shift) made the editor's.
func _sync_tree_selection() -> void:
	_tree_due = false
	var picked := []
	var it := _parts.get_next_selected(null)
	while it:
		var n = it.get_metadata(0)
		if n is MeshInstance3D:
			if not n in picked:
				picked.append(n)
		elif n is Node:
			for q in curve_tools.group_parts(n):   # (a part - a group: all its solids)
				if not q in picked:
					picked.append(q)
		it = _parts.get_next_selected(it)
	if picked.is_empty():
		return
	var active: MeshInstance3D = _tree_active if _tree_active in picked else picked.back()
	var order := selected_parts().filter(func(p): return p in picked and p != active)
	for p in picked:
		if not p in order and p != active:
			order.append(p)
	order.append(active)
	if mode == "edit" and active != part:
		_leave_edit(true)
	sel_parts = order
	part = active
	_menu_prev = null
	_show_part()
	_show_material_list()
	_update_ui()
	view.request()
	curve_tools.solid_chosen(active if picked.size() == 1 else null)


## The left panel shows "models" (the files), "shapes" (the shape library) or "materials" (the material library).
func set_left_tab(t: String) -> void:
	left_tab = t
	for k in _tab_btns:
		(_tab_btns[k] as Button).set_pressed_no_signal(k == t)
	_models_box.visible = t == "models"
	for k in _view_btns:
		(_view_btns[k] as Button).visible = t == "models"
	shape_tools.browser.visible = false   # (the old shape library: the primitives' tab shows ECurve primitives)
	if has_meta("prims") and is_instance_valid(get_meta("prims")):
		(get_meta("prims") as Control).visible = t == "shapes"
	mat_tools.browser.visible = t == "materials"
	if t == "materials":
		mat_tools.refresh_model()
		mat_tools.browser.refill()
	var c := ConfigFile.new()
	c.load(LAYOUT)
	c.set_value("mesh", "left_tab", t)
	c.save(LAYOUT)


## Boolean `op` - "union", "difference", "intersection", "slice" - of parts `a` and `b` (null:
## the two selected); `now`: worked out here (else on a worker).
func boolean(op: String, a: MeshInstance3D = null, b: MeshInstance3D = null, now := false) -> bool:
	return shape_tools.boolean(op, a, b, now)


## Adds shape `id` of the library as a part, now (the browser makes it on a worker).
func add_shape_now(id: String, at := Vector3.INF) -> MeshInstance3D:
	return shape_tools.add_shape_now(id, at)


func _can_drop_shape(at: Vector2, data: Variant) -> bool:
	var ok: bool = data is Dictionary and (data.has("mesh_shape") or data.has("ecurve_prim") or data.has("ecurve_model"))
	if ok:
		_drop_marker(at, data)   # (where it will land, shown while it's dragged)
	return ok or mat_tools.can_drop(data)


# --- the drop marker: where a dragged shape or object will land ---------------------------

const DROP_COL := Color(0.35, 0.9, 1.0)


## A shape, primitive or ECurve object dragged over the view: a ring on the surface under the pointer
## (lying on it), a stem up from it to the point and, for an ECurve object, its bounds as they'll stand
## there (the object read on a worker the first time - the drop then uses that read, no wait).
func _drop_marker(at: Vector2, data: Dictionary) -> void:
	if view == null or view.world == null:
		return
	var mk = (get_meta("drop_marker") if has_meta("drop_marker") else null)
	if mk == null or not is_instance_valid(mk):
		mk = _make_drop_marker()
		set_meta("drop_marker", mk)
	var hit: Array = shape_tools.drop_hit(at)
	var p: Vector3 = hit[0]
	var n: Vector3 = hit[1]
	var ring := mk.get_node("Ring") as MeshInstance3D
	var x := n.cross(Vector3.FORWARD if absf(n.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	var s := maxf(view.dist * 0.03, 0.002)   # (the same size on screen at any zoom)
	ring.global_transform = Transform3D(Basis(x, n, x.cross(n)).scaled(Vector3.ONE * s), p)
	var bx := mk.get_node("Bounds") as MeshInstance3D
	bx.visible = false
	if data.has("ecurve_model"):
		var b = _drop_bounds(str(data["ecurve_model"]))
		if b is AABB:
			bx.mesh = _box_lines(b)
			bx.global_transform = Transform3D(Basis(), p)
			bx.visible = true
	(mk as Node3D).visible = true


func _make_drop_marker() -> Node3D:
	var mk := Node3D.new()
	mk.name = "DropMarker"
	var line := StandardMaterial3D.new()
	line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line.no_depth_test = true
	line.cull_mode = BaseMaterial3D.CULL_DISABLED
	line.render_priority = 10
	line.albedo_color = DROP_COL
	var fill := line.duplicate() as StandardMaterial3D
	fill.albedo_color = Color(DROP_COL, 0.22)
	# the ring: a circle, a filled disc, four ticks out from it and a stem along the normal (radius 1)
	var am := ArrayMesh.new()
	var lv := PackedVector3Array()
	var dv := PackedVector3Array()
	var k := 48
	for i in k:
		var a0 := TAU * i / k
		var a1 := TAU * (i + 1) / k
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		lv.append_array([p0, p1])
		dv.append_array([Vector3.ZERO, p1, p0])
	for dd in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		lv.append_array([dd * 0.55, dd * 1.45])
	lv.append_array([Vector3.ZERO, Vector3.UP * 2.0])
	var la := []
	la.resize(Mesh.ARRAY_MAX)
	la[Mesh.ARRAY_VERTEX] = lv
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, la)
	am.surface_set_material(0, line)
	var da := []
	da.resize(Mesh.ARRAY_MAX)
	da[Mesh.ARRAY_VERTEX] = dv
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, da)
	am.surface_set_material(1, fill)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = am
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mk.add_child(ring)
	var bx := MeshInstance3D.new()
	bx.name = "Bounds"
	bx.material_override = line
	bx.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mk.add_child(bx)
	view.world.add_child(mk)
	return mk


## An AABB's twelve edges as lines.
static func _box_lines(b: AABB) -> ArrayMesh:
	var v := PackedVector3Array()
	for e in [[0, 1], [1, 3], [3, 2], [2, 0], [4, 5], [5, 7], [7, 6], [6, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		v.append_array([b.get_endpoint(e[0]), b.get_endpoint(e[1])])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, a)
	return m


## A dragged ECurve object's bounds (in its own space - where it's set down, its origin): read on a worker
## the first time (null until then). The read object is kept for the drop.
func _drop_bounds(res_path: String) -> Variant:
	var c: Dictionary = get_meta("drop_reads", {})
	if not c.has(res_path):
		var file := _model_source(res_path, _variant_to_open(res_path, -1))
		var h := [null, null]
		var id := WorkerThreadPool.add_task(func():
			var src: Node3D = MeshIO.read(file)
			var bb = null
			if src != null:
				for m in src.find_children("*", "MeshInstance3D", true, false):
					if (m as MeshInstance3D).mesh == null:
						continue
					var ab: AABB = _rel_xf(src, m) * (m as MeshInstance3D).mesh.get_aabb()
					bb = ab if bb == null else (bb as AABB).merge(ab)
			h[0] = src
			h[1] = bb, false, "ECurves: read a dragged object")
		c[res_path] = [id, h]
		set_meta("drop_reads", c)
		return null
	if not _read_done(c[res_path]):
		return null
	return c[res_path][1][1]


## A drop read's task finished (waited for once, its id then -1).
static func _read_done(e: Array) -> bool:
	if int(e[0]) < 0:
		return true
	if not WorkerThreadPool.is_task_completed(int(e[0])):
		return false
	WorkerThreadPool.wait_for_task_completion(int(e[0]))
	e[0] = -1
	return true


## The drag over: the marker hidden, the objects read for it and not dropped let go.
func _drop_marker_end() -> void:
	var mk = (get_meta("drop_marker") if has_meta("drop_marker") else null)
	if mk != null and is_instance_valid(mk):
		(mk as Node3D).visible = false
	var c: Dictionary = get_meta("drop_reads", {})
	for k in c.keys():
		var e: Array = c[k]
		if not _read_done(e):
			continue   # (still reading: let go once it's done - never waited for here)
		if e[1][0] != null and is_instance_valid(e[1][0]):
			(e[1][0] as Node).free()
		c.erase(k)
	if c.is_empty():
		remove_meta("drop_reads")


## The object read for the marker while it was dragged, taken for the drop (null: not read yet).
func _take_drop_read(res_path: String) -> Node3D:
	var c: Dictionary = get_meta("drop_reads", {})
	if not c.has(res_path):
		return null
	var e: Array = c[res_path]
	if not _read_done(e):
		return null
	c.erase(res_path)
	return e[1][0]


## A shape dropped in the view: added there; a material: given to the surface under it.
func _drop_shape(at: Vector2, data: Variant) -> void:
	if mat_tools.can_drop(data):
		mat_tools.drop(at, data)
		return
	if (data as Dictionary).has("ecurve_prim"):
		curve_tools.add_curve_primitive(str(data["ecurve_prim"]), shape_tools.drop_point(at))
		return
	if (data as Dictionary).has("ecurve_model"):
		var pre := _take_drop_read(str(data["ecurve_model"]))
		if pre != null:
			_add_read_model(pre, str(data["ecurve_model"]), shape_tools.drop_point(at))   # (read while it was dragged)
		else:
			add_model_into(str(data["ecurve_model"]), shape_tools.drop_point(at))
		_drop_marker_end()
		return
	shape_tools.add_shape(str(data["mesh_shape"]), shape_tools.drop_point(at))


## ECurve object `res_path` added into the open one at `at` (model space; INF - the middle): its parts in a
## new collection of their own, made ECurve solids (one undo step for the adding).
func add_model_into(res_path: String, at := Vector3.INF, now := false) -> Node3D:
	if model == null:
		new_model(true)
	var file := _model_source(res_path, _variant_to_open(res_path, -1))
	if not now:
		# (read on a worker - a big model doesn't stop the editor; added once it's read)
		if has_meta("drop_job"):
			return null
		var h := [null]
		var id := WorkerThreadPool.add_task(func(): h[0] = MeshIO.read(file), false, "ECurves: read a dropped object")
		set_meta("drop_job", [id, h, res_path, at])
		_say("Reading %s..." % res_path.get_file())
		return null
	return _add_read_model(MeshIO.read(file), res_path, at)


## (each frame) A conversion's storing, first: its skinned solids' meshes read, ~4 ms of them a frame; then
## their weights worked out on a worker (each solid's new mesh made there too).
func _store_gather_step() -> void:
	var b: Dictionary = get_meta("store_gather")
	var ga: Dictionary = b["gather"]
	var qs: Array = ga["qs"]
	var t0 := Time.get_ticks_usec()
	while int(ga["i"]) < qs.size() and Time.get_ticks_usec() - t0 < 4000:
		var q = qs[int(ga["i"])]
		ga["i"] = int(ga["i"]) + 1
		if not (q is MeshInstance3D) or not is_instance_valid(q) or not (q as Node).has_meta("weight_src") or (q as MeshInstance3D).mesh == null:
			continue
		var mq := q as MeshInstance3D
		var ms := []
		var mats := []
		for si in mq.mesh.get_surface_count():
			ms.append(mq.mesh.surface_get_arrays(si))
			mats.append(mq.mesh.surface_get_material(si))
		var src: Mesh = mq.get_meta("weight_src")
		var ss := []
		for si in src.get_surface_count():
			ss.append(src.surface_get_arrays(si))
		(ga["pieces"] as Array).append([mq, mq.mesh, ms, ss, mats])
	if int(ga["i"]) < qs.size():
		return
	remove_meta("store_gather")
	b.erase("gather")
	var pieces: Array = ga["pieces"]
	var h := [null]
	var jobs := pieces.map(func(e): return [e[2], e[3], e[4]])
	var id := WorkerThreadPool.add_task(func():
		var res := []
		for jb in jobs:
			var wa: Array = MeshBind.weighted_arrays(jb[0], jb[1])
			res.append([wa, MeshBind.mesh_of(wa, jb[2]) if not wa.is_empty() else null])
		h[0] = res, false, "ECurves: weights")
	b["weighted"] = [id, h, pieces]
	set_meta("store_job", b)


## (each frame) A conversion's storing: once its weights are worked out, the solids given them and the
## object written.
func _store_step() -> void:
	var b: Dictionary = get_meta("store_job")
	var w: Array = b["weighted"]
	if not WorkerThreadPool.is_task_completed(int(w[0])):
		return
	WorkerThreadPool.wait_for_task_completion(int(w[0]))
	remove_meta("store_job")
	var res: Array = w[1][0]
	for i in (w[2] as Array).size():
		var e: Array = w[2][i]
		var q = e[0]
		if is_instance_valid(q) and (q as MeshInstance3D).mesh == e[1] and res[i][1] != null:
			(q as MeshInstance3D).set_meta("weighted", [e[1], res[i][1]])
	store_converted(b)


## (each frame) A dropped object read on a worker: added once it's in.
func _drop_step() -> void:
	if not has_meta("drop_job"):
		return
	var j: Array = get_meta("drop_job")
	if not WorkerThreadPool.is_task_completed(int(j[0])):
		return
	WorkerThreadPool.wait_for_task_completion(int(j[0]))
	remove_meta("drop_job")
	_add_read_model(j[1][0], str(j[2]), j[3])


func _add_read_model(src: Node3D, res_path: String, at: Vector3) -> Node3D:
	if src == null:
		_say("Couldn't read %s." % res_path)
		return null
	var ps: Array = []
	for m in src.find_children("*", "MeshInstance3D", true, false):
		if (m as MeshInstance3D).mesh != null:
			ps.append(m)
	if ps.is_empty():
		_say("%s has no solids to add." % res_path.get_file())
		return null
	var g := Node3D.new()
	g.name = _unique(res_path.get_file().get_basename().capitalize())
	curve_tools._mark_group(g)
	if at != Vector3.INF:
		g.position = at
	var copies := []
	for m: MeshInstance3D in ps:
		var c := MeshInstance3D.new()
		c.name = str(m.name)
		c.mesh = m.mesh
		c.material_override = m.material_override   # (its looks: overrides kept)
		if m.skin:
			c.set_meta("src_skin", m.skin)   # (its bones: where its weights belong - kept with it, put back when it's stored)
			var sk0 := m.get_node_or_null(m.skeleton) as Skeleton3D
			if sk0:
				var bn := PackedStringArray()
				for bi in m.skin.get_bind_count():
					var b0 := m.skin.get_bind_bone(bi)
					var nm0 := str(m.skin.get_bind_name(bi))
					bn.append(nm0 if nm0 != "" else (sk0.get_bone_name(b0) if b0 >= 0 and b0 < sk0.get_bone_count() else ""))
				c.set_meta("src_bones", bn)   # (each bind's bone by name: its solids named after them)
		for si in m.mesh.get_surface_count():
			if m.get_surface_override_material(si):
				c.set_surface_override_material(si, m.get_surface_override_material(si))
		c.transform = src.global_transform.affine_inverse() * m.global_transform if src.is_inside_tree() else _rel_xf(src, m)
		for k in ["curve_solid", "extras"]:
			if m.has_meta(k):
				c.set_meta(k, m.get_meta(k))
		var ex = m.get_meta("extras", {})
		if ex is Dictionary and ex.get("atrapos_curves") is Dictionary:
			c.set_meta("curve_solid", ex["atrapos_curves"])
		if c.has_meta("curve_solid") and m.skin:
			c.set_meta("weight_src", m.mesh)   # (a stored skinned ECurve solid: its weights, put back when stored)
			c.set_meta("ecurve_skin", m.skin)
		copies.append(c)
	# (a character's skeleton: its bones copied beside its solids - the T-pose turns each solid by its
	# bone; not one of the solids, never stored with them)
	var rig: Skeleton3D = null
	for m: MeshInstance3D in ps:
		var sk0 := m.get_node_or_null(m.skeleton) as Skeleton3D if m.skin else null
		if sk0 == null:
			continue
		rig = Skeleton3D.new()
		rig.name = "Rig"
		rig.set_meta("ecurve_rig", true)
		for bi in sk0.get_bone_count():
			rig.add_bone(sk0.get_bone_name(bi))
		for bi in sk0.get_bone_count():
			rig.set_bone_parent(bi, sk0.get_bone_parent(bi))
			rig.set_bone_rest(bi, sk0.get_bone_rest(bi))
		rig.reset_bone_poses()
		rig.transform = src.global_transform.affine_inverse() * sk0.global_transform if src.is_inside_tree() else _rel_xf(src, sk0)
		break
	src.free()
	# (an ECurve object stored before: its edges come with it - their ids made new, so they don't meet
	# the open object's)
	# (beside the file it was read from - the model's active variant, not the open object's)
	var cf := _model_source(res_path, _variant_to_open(res_path, -1)) + ".curves.json"
	if FileAccess.file_exists(cf):
		var jd = JSON.parse_string(FileAccess.get_file_as_string(cf))
		if jd is Dictionary:
			var idmap := {}
			for c in curve_tools.from_json(jd.get("curves", [])):
				var old_id := int(c.get("id", -1))
				curve_tools._fresh(c)
				idmap[old_id] = int(c["id"])
				curve_tools.curves.append(c)
			for c in copies:
				if c.has_meta("curve_solid"):
					c.set_meta("curve_solid", curve_tools.remap_spec(c.get_meta("curve_solid"), idmap))
	var mdl := model
	_do("Add " + str(g.name), func():
		mdl.add_child(g)
		g.owner = mdl
		for c in copies:
			g.add_child(c)
			c.owner = mdl
		if rig and rig.get_parent() == null:
			g.add_child(rig)
			rig.owner = mdl
		_fill_parts()
		curve_tools.refresh_solids()
		curve_tools._refresh_panel()
		view.request(), func():
		mdl.remove_child(g)
		_fill_parts()
		curve_tools._refresh_panel()
		view.request(), [g] + ([rig] if rig else []))
	curve_tools.convert_parts(copies, {"kind": "drop", "path": res_path, "group": g})   # (any not ECurve yet: made so, in the background - then stored so)
	_say("%s added: %d solid%s in a collection of their own." % [res_path.get_file(), copies.size(), "" if copies.size() == 1 else "s"])
	return g


## A finished conversion batch stored, so the object isn't converted again: the open object (`kind`
## "open") saved as it is now - a new variant of a game model, which the game then uses; a dropped object
## ("drop") written as its source model's new variant - its converted solids in place of its meshes, each
## with its materials and, a skinned one, its skin and the weights its old mesh had.
func store_converted(b: Dictionary) -> void:
	var pth := str(b.get("path", ""))
	if pth == "" or not EditTarget.writable():
		return
	if not b.has("weighted"):
		# (first the skinned solids' weights, on a worker - hundreds of them: never on this thread; their
		# meshes read here a few a frame first - _store_gather_step)
		var root_n: Node = b.get("group") if b.get("group") is Node else model
		if root_n == null or not is_instance_valid(root_n):
			return
		b["gather"] = {"qs": root_n.find_children("*", "MeshInstance3D", true, false), "i": 0, "pieces": []}
		set_meta("store_gather", b)
		_say("Storing %s as an ECurve object..." % pth.get_file())
		return
	if str(b.get("kind", "")) == "open":
		if pth != path or model == null:
			return
		# (written on a worker: a copy of the object as it is - its skinned solids given their weights
		# and skins, every solid's recipe and every collection in its extras)
		var cp: Node3D = model.duplicate()
		for q: MeshInstance3D in cp.find_children("*", "MeshInstance3D", true, false):
			var wc0: Array = q.get_meta("weighted", [])
			if wc0.size() == 2 and q.has_meta("ecurve_skin"):
				q.mesh = wc0[1]
				q.skin = q.get_meta("ecurve_skin")
			var ex0: Dictionary = (q.get_meta("extras", {}) as Dictionary).duplicate() if q.get_meta("extras", {}) is Dictionary else {}
			if q.has_meta("curve_solid"):
				ex0["atrapos_curves"] = q.get_meta("curve_solid")
			q.set_meta("extras", ex0)
		for n0 in cp.find_children("*", "Node3D", true, false):
			if n0.has_meta("part_group"):
				var ex1: Dictionary = (n0.get_meta("extras", {}) as Dictionary).duplicate() if n0.get_meta("extras", {}) is Dictionary else {}
				ex1["atrapos_group"] = true
				n0.set_meta("extras", ex1)
		var ofile := _write_target(path)
		var ocs: Array = curve_tools.to_json(curve_tools.curves)
		var oh := [null]
		var oid := WorkerThreadPool.add_task(func():
			var ocjson := JSON.stringify({"curves": ocs}, "\t")   # (turned to text there: thousands of edges)
			var e := MeshIO.write(cp, ofile)
			if e == OK:
				var fa := FileAccess.open(ofile + ".curves.json", FileAccess.WRITE)
				if fa:
					fa.store_string(ocjson)
			oh[0] = e, false, "ECurves: store")
		set_meta("store_write", [oid, oh, pth, cp, "open"])
		return
	var g = b.get("group")
	if not (g is Node3D) or not is_instance_valid(g):
		return
	# (written on a worker: its copy made here, the model read, put together and written there)
	var copy: Node3D = (g as Node3D).duplicate()
	for q: MeshInstance3D in copy.find_children("*", "MeshInstance3D", true, false):
		var wc: Array = q.get_meta("weighted", [])
		if wc.size() == 2:
			q.mesh = wc[1]
			q.set_meta("weighted", [wc[1], wc[1]])
	var ids := {}
	for q: MeshInstance3D in copy.find_children("*", "MeshInstance3D", true, false):
		for id in curve_tools.spec_ids(q.get_meta("curve_solid", {})):
			ids[int(id)] = true
	var cs := []
	for c in curve_tools.curves:
		if ids.has(int(c.get("id", -1))):
			cs.append(c)
	var cjs: Array = curve_tools.to_json(cs)
	var n := ModelOverride.add(pth)
	var file := ModelOverride.file_of(pth, n)
	var src_file := _model_source(pth, _variant_to_open(pth, n - 1) if n > 1 else 0)
	var h := [null]
	var id2 := WorkerThreadPool.add_task(func(): h[0] = _store_ecurve_work(src_file, copy, file, JSON.stringify({"curves": cjs}, "\t")), false, "ECurves: store")
	set_meta("store_write", [id2, h, pth, copy])


## (each frame) A dropped object's store being written on a worker: done - the game told.
func _store_write_step() -> void:
	var w: Array = get_meta("store_write")
	if not WorkerThreadPool.is_task_completed(int(w[0])):
		return
	WorkerThreadPool.wait_for_task_completion(int(w[0]))
	remove_meta("store_write")
	if is_instance_valid(w[3]):
		(w[3] as Node).free()
	if int(w[1][0]) == OK:
		_forget_game(str(w[2]))
		if w.size() > 4 and str(w[2]) == path:
			if MeshIO.is_character(path):
				_write_material_table(path)
			dirty = false
			_refresh_variants()
			_update_ui()
		_start_scan()
		_say("%s stored as an ECurve object - %s again, it needn't be converted." % [str(w[2]).get_file(), "opened" if w.size() > 4 else "added"])
	else:
		_say("Couldn't store %s (%s)." % [str(w[2]).get_file(), error_string(int(w[1][0]))])


## (on a worker: nothing here is in the scene) Model `src_file` read, its meshes replaced by their
## converted counterparts in `g` (by name - a solid, or a collection of its pieces), skinned ones bound
## back to its skeleton, written to `file` with its edges (`cjson`) beside it.
static func _store_ecurve_work(src_file: String, g: Node3D, file: String, cjson: String) -> int:
	var root := MeshIO.read(src_file)
	if root == null:
		return FAILED
	var by_name := {}
	for c in g.get_children():
		# (a mesh made pieces: its collection - "Body solids" for a character's Body)
		by_name[str(c.name).trim_suffix(" solids")] = c
	for m: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		var c = by_name.get(str(m.name))
		if c == null:
			continue
		var skel: Node = m.get_node_or_null(m.skeleton) if m.skin != null else null
		var dup: Node3D = (c as Node3D).duplicate()
		var parent := m.get_parent()
		var at := m.get_index()
		var xf := m.transform
		parent.remove_child(m)
		dup.name = str(c.name)
		parent.add_child(dup)
		parent.move_child(dup, at)
		dup.transform = xf
		var pieces: Array = [dup] if dup is MeshInstance3D else []
		pieces.append_array(dup.find_children("*", "MeshInstance3D", true, false))
		for q: MeshInstance3D in pieces:
			var spec: Dictionary = q.get_meta("curve_solid", {})
			var ex: Dictionary = (q.get_meta("extras", {}) as Dictionary).duplicate() if q.get_meta("extras", {}) is Dictionary else {}
			if not spec.is_empty():
				ex["atrapos_curves"] = spec
			q.set_meta("extras", ex)
			var sk: Skin = q.get_meta("ecurve_skin") if q.has_meta("ecurve_skin") else m.skin
			if skel and sk:
				var src: Mesh = q.get_meta("weight_src") if q.has_meta("weight_src") else null
				if src:
					var wc: Array = q.get_meta("weighted", [])
					var wm: ArrayMesh = wc[1] if wc.size() == 2 and wc[0] == q.mesh else MeshBind.transfer_weights(q.mesh, src)
					if wm:
						q.mesh = wm
				q.skin = sk
				q.skeleton = q.get_path_to(skel)
		m.free()
	for n in root.find_children("*", "Node3D", true, false):
		if n.has_meta("part_group"):
			var ex2: Dictionary = (n.get_meta("extras", {}) as Dictionary).duplicate() if n.get_meta("extras", {}) is Dictionary else {}
			ex2["atrapos_group"] = true
			n.set_meta("extras", ex2)
	var err := MeshIO.write(root, file)
	if err == OK:
		var fa := FileAccess.open(file + ".curves.json", FileAccess.WRITE)
		if fa:
			fa.store_string(cjson)
	root.free()
	return err


## A stored skinned ECurve solid opened: its saved (skinned) mesh where its weights come from, its skin
## kept for saving - while it's edited it's drawn at rest, its mesh made again from its edges.
func _ecurve_skin(p: MeshInstance3D) -> void:
	if p.skin == null or str((p.get_meta("curve_solid", {}) as Dictionary).get("kind", "")) != "edges":
		return
	p.set_meta("weight_src", p.mesh)
	p.set_meta("ecurve_skin", p.skin)
	p.skin = null


## `n`'s transform relative to `root` (neither in the tree).
static func _rel_xf(root: Node, n: Node) -> Transform3D:
	var x := Transform3D()
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			x = (cur as Node3D).transform * x
		cur = cur.get_parent()
	return x



# --- the knife (K) -------------------------------------------------------------------
# Click points on the surface: the cut runs over the faces between them (each click snaps
# to a face's corner or the middle of a side when near - Ctrl: not); Enter or Space cuts,
# Backspace takes the last point back, Esc or a right click stops. Shift+K cuts right
# through the part, front and back, along the line drawn on the screen. With symmetry
# on, the mirror images are cut too.

## The cut being drawn ({} - none): "clicks" ([{o, d: the ray (part space), eye, persp,
## pos, node}]), "through".
var knife := {}
var _knife_centre := Vector3.ZERO
var _ngons_btn: Button
const SNAP_PX := 14.0


## The knife's toolbar button.
func _knife_button() -> Button:
	var b := Button.new()
	b.name = "KnifeButton"
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): begin_knife())
	return EditorIcons.dress(b, "m_knife", EditorIcons.tip("Knife", "K / Shift+K",
		"Edit mode: cuts the faces along a path - click points on the surface (each snaps to a corner\nor the middle of a side nearby; Ctrl: no snapping), Enter or Space cuts, Backspace takes the\nlast point back, Esc or right-click stops. Shift+K cuts right through the solid, front and back."))


## The faces / triangles view toggle's button (pressed: every triangle's edges shown).
func _ngons_button() -> Button:
	var b := Button.new()
	b.name = "NgonsButton"
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.button_pressed = view != null and view.show_tris
	b.toggled.connect(set_tris_view)
	_ngons_btn = b
	return EditorIcons.dress(b, "m_ngons", EditorIcons.tip("N-gons / triangles", "",
		"Edit mode shows the faces - quads and n-gons - without the diagonals of their triangles;\npressed, it shows every triangle."))


## Edit mode's wireframe: every triangle (`on`) or the faces (n-gons).
func set_tris_view(on: bool) -> void:
	if view == null:
		return
	view.show_tris = on
	if _ngons_btn and is_instance_valid(_ngons_btn):
		_ngons_btn.set_pressed_no_signal(on)
	if em:
		_overlays()


func begin_knife(through := false) -> void:
	if mode != "edit" or em == null or part == null:
		_say("Knife: select a solid and press Tab for edit mode first.")
		return
	_cancel_xf()
	knife = {"clicks": [], "through": through}
	_knife_centre = em.aabb().get_center()
	view.knife_on = true
	view.knife_through = through
	_sync_gizmo()
	_knife_show()
	_say(("Cut through: click two points across the solid" if through else "Knife: click points on the surface") +
		" - Enter or Space cuts, Backspace takes one back, Esc stops (Ctrl: no snapping).")


func knife_cancel() -> void:
	if knife.is_empty():
		return
	knife = {}
	_sync_gizmo()
	if view:
		view.knife_on = false
		view.knife_pts = PackedVector3Array()
		view.knife_kinds = PackedInt32Array()
		view.knife_next = Vector3.INF
		view.hint = ""
		view.queue_redraw()


## The last point placed taken back.
func knife_back() -> void:
	if knife.is_empty():
		return
	var cl: Array = knife["clicks"]
	if not cl.is_empty():
		cl.pop_back()
	_knife_show()


## A point placed where screen point `at` meets the surface (`snap`: onto a corner or a side's
## middle near it). False: not on the part.
func knife_add(at: Vector2, snap := true) -> bool:
	if knife.is_empty():
		return false
	var c := _knife_click(at, snap)
	if c.is_empty():
		return false
	(knife["clicks"] as Array).append(c)
	_knife_show()
	return true


## A point placed at `pos` (the part's space) as seen along `dir` (`snap`: onto a corner or a
## side within a thousandth of the part's size; tests and typed cuts).
func knife_add_local(pos: Vector3, dir: Vector3, snap := true) -> bool:
	if knife.is_empty():
		begin_knife()
		if knife.is_empty():
			return false
	dir = dir.normalized()
	var o := pos - dir * maxf(1.0, em.aabb().size.length() * 2.0)
	var c := {"o": o, "d": dir, "eye": o, "persp": false, "pos": pos, "node": {}}
	if not knife.get("through", false):
		_tm_ready()
		var hit := _em_tm.intersect_ray(o, dir)
		if hit.is_empty():
			return false
		var tol: float = em.aabb().size.length() * 0.001 if snap else 0.0
		c["node"] = em.knife_node(int(hit["face_index"]), hit["position"], -1, tol)
		c["pos"] = c["node"]["pos"]
	(knife["clicks"] as Array).append(c)
	_knife_show()
	return true


func _tm_ready() -> void:
	if _em_tm == null:
		_wait_tm()
	if _em_tm == null:
		_em_tm = em.triangle_mesh()


func _knife_click(at: Vector2, snap: bool) -> Dictionary:
	var r := view.ray(at)
	var g := part.global_transform
	var inv := g.affine_inverse()
	var c := {"o": inv * (r[0] as Vector3), "d": (inv.basis * (r[1] as Vector3)).normalized(),
		"eye": inv * view.cam.global_position, "persp": view.cam.projection == Camera3D.PROJECTION_PERSPECTIVE, "node": {}}
	if knife.get("through", false):
		c["pos"] = inv * view.on_view_plane(at, g * _knife_centre)
		return c
	var t := _pick_tri(at)
	if t < 0:
		return {}
	var node: Dictionary = em.node_face(t, _last_hit)
	if snap:
		var loop: PackedInt32Array = em.poly_loop(t)
		if loop.is_empty():
			loop = em.tris.slice(t * 3, t * 3 + 3)
		var bd := SNAP_PX
		for p in loop:
			var d := _screen(p).distance_to(at)
			if d < bd:
				bd = d
				node = em.node_point(p, em.points[p])
		for i in loop.size():
			var a := loop[i]
			var b := loop[(i + 1) % loop.size()]
			var mid: Vector3 = (em.points[a] + em.points[b]) * 0.5
			var d := view.project(g * mid).distance_to(at)
			var e: int = em.edge(a, b)
			if d < bd and e >= 0:
				bd = d
				node = em.node_on_edge(e, 0.5)
	c["node"] = node
	c["pos"] = node["pos"]
	return c


## The cut drawn in the view (and the spot the mouse at `at` would add, if given).
func _knife_show(at := Vector2(-1, -1)) -> void:
	if knife.is_empty() or part == null:
		return
	var g := part.global_transform
	var pts := PackedVector3Array()
	var kinds := PackedInt32Array()
	for c in knife["clicks"]:
		pts.append(g * (c["pos"] as Vector3))
		kinds.append(int((c["node"] as Dictionary).get("k", 2)))
	view.knife_pts = pts
	view.knife_kinds = kinds
	view.knife_next = Vector3.INF
	view.knife_mouse = at
	if at.x >= 0.0:
		var c := _knife_click(at, not Input.is_key_pressed(KEY_CTRL))
		if not c.is_empty():
			view.knife_next = g * (c["pos"] as Vector3)
			view.knife_next_kind = int((c["node"] as Dictionary).get("k", 2))
	view.hint = "%s  %d point%s" % ["Cut through" if knife["through"] else "Knife", pts.size(), "" if pts.size() == 1 else "s"]
	view.request()


## The mirror images of the cut to make too: [[axes flipped], ...] (none flipped first).
func _knife_variants() -> Array:
	var out := [[]]
	for a in 3:
		if sym[a]:
			for v in out.duplicate():
				out.append((v as Array) + [a])
	return out


static func _flip(v: Vector3, axes: Array) -> Vector3:
	for a in axes:
		v[a] = -v[a]
	return v


## The cut's chains (EditMesh.knife_walk / knife_slice) for the clicks mirrored across `axes`
## ([] - can't follow the surface between two of them).
func _knife_chains(clicks: Array, axes: Array) -> Array:
	var cl := []
	for c: Dictionary in clicks:
		var m := {"o": _flip(c["o"], axes), "d": _flip(c["d"], axes), "eye": _flip(c["eye"], axes), "persp": c["persp"],
			"pos": _flip(c["pos"], axes), "node": c["node"]}
		if not knife["through"] and not axes.is_empty():
			# (the mirror image found on the mesh: the mirrored ray, snapped as the click was)
			_tm_ready()
			var hit := _em_tm.intersect_ray(m["o"], m["d"])
			if hit.is_empty():
				return []
			m["node"] = em.knife_node(int(hit["face_index"]), hit["position"], int((c["node"] as Dictionary).get("k", 2)))
			m["pos"] = m["node"]["pos"]
		cl.append(m)
	var chains := []
	if knife["through"]:
		for i in cl.size() - 1:
			var c0: Dictionary = cl[i]
			var c1: Dictionary = cl[i + 1]
			var o: Vector3
			var n: Vector3
			var sides := []
			if c0["persp"] and c1["persp"] and (c0["eye"] as Vector3).distance_to(c1["eye"]) < 1e-5:
				o = c0["eye"]
				var d0: Vector3 = c0["d"]
				var d1: Vector3 = c1["d"]
				n = d0.cross(d1)
				var m0 := n.cross(d0)
				var m1 := n.cross(d1)
				sides = [[o, m0 if m0.dot(d1) > 0.0 else -m0], [o, m1 if m1.dot(d0) > 0.0 else -m1]]
			else:
				var dv: Vector3 = ((c0["d"] as Vector3) + (c1["d"] as Vector3)).normalized()
				var span: Vector3 = (c1["o"] as Vector3) - (c0["o"] as Vector3)
				o = c0["o"]
				n = span.cross(dv)
				var side := span - dv * span.dot(dv)
				sides = [[c0["o"], side], [c1["o"], -side]]
			if n.length_squared() < 1e-20:
				continue
			chains += em.knife_slice(o, n, sides)
		return chains
	var nodes := []
	var segs := PackedInt32Array()
	for i in cl.size() - 1:
		var c0: Dictionary = cl[i]
		var c1: Dictionary = cl[i + 1]
		var a: Vector3 = c0["pos"]
		var b: Vector3 = c1["pos"]
		var n: Vector3
		if c0["persp"] and c1["persp"] and (c0["eye"] as Vector3).distance_to(c1["eye"]) < 1e-5:
			n = (a - (c0["eye"] as Vector3)).cross(b - (c0["eye"] as Vector3))
		else:
			n = (b - a).cross(((c0["d"] as Vector3) + (c1["d"] as Vector3)).normalized())
		var w: Dictionary = em.knife_walk(c0["node"], c1["node"], n, (c0["d"] as Vector3) + (c1["d"] as Vector3))
		if w.is_empty():
			return []
		var wn: Array = w["nodes"]
		nodes += wn if nodes.is_empty() else wn.slice(1)
		segs.append_array(w["segs"])
	return [{"nodes": nodes, "segs": segs}]


## Makes the cut drawn (one undo step); the new edges selected. False: nothing cut (the note says why).
func knife_confirm() -> bool:
	if knife.is_empty() or em == null:
		return false
	var clicks: Array = knife["clicks"]
	if clicks.size() < 2:
		_say("Knife: place two points or more (Esc: stop).")
		return false
	var t0 := Time.get_ticks_usec()
	var chains := []
	var variants := _knife_variants()
	for vi in variants.size():
		var axes: Array = variants[vi]
		# (a cut across the seam: its mirror image would cross it - made once)
		if not axes.is_empty() and not chains.is_empty():
			var across := false
			for a in axes:
				var sides := [false, false]
				for c in chains[0]["nodes"]:
					var v: float = (c["pos"] as Vector3)[a]
					if absf(v) > 1e-5:
						sides[0 if v < 0.0 else 1] = true
				across = across or (sides[0] and sides[1]) or not (sides[0] or sides[1])
			if across:
				continue
		var cs := _knife_chains(clicks, axes)
		if cs.is_empty():
			if vi == 0:
				_say("Knife: it can't follow the surface from one point to the next (a gap or an open edge between them).")
				return false
			continue
		chains += cs
	var before := _snap()
	var res: Dictionary = em.knife_apply(chains)
	if not res["ok"]:
		_say("Knife: %s - nothing cut." % res["why"])
		return false
	knife_cancel()
	_resize_sel()
	sel_p.fill(0)
	sel_e.fill(0)
	sel_t.fill(0)
	sel_pa.fill(0)
	var cut: PackedInt32Array = res["cut"]
	for i in range(0, cut.size(), 2):
		var e: int = em.edge(cut[i], cut[i + 1])
		if e >= 0:
			sel_e[e] = 1
	var keep := 2 if sel_kind == 2 else sel_kind
	sel_kind = 1
	_derive_sel()
	sel_kind = 1 if keep == 2 else keep
	_edit_done("Knife", before)
	_update_ui()
	_say("Knife: %d new points, %d new edges (%.1f ms)." % [(res["points"] as PackedInt32Array).size(), cut.size() / 2, (Time.get_ticks_usec() - t0) / 1000.0])
	return true


# --- dissolve (Ctrl+X) -----------------------------------------------------------------

## Dissolves the selection (EditMesh.dissolve): vertex mode the points, edge mode the edges,
## face mode the faces, Auto all it has picked - and with symmetry on their mirror twins.
## One undo step; the faces made are selected (face and Auto mode).
func dissolve_selected() -> void:
	if em == null:
		return
	knife_cancel()
	var kinds: Array = [[0], [1], [2], [0, 1, 2]][sel_kind]
	var pts := {}
	var eds := {}
	var ts := PackedByteArray()
	ts.resize(em.tri_count())
	for kind in kinds:
		var arr: PackedByteArray = [sel_pa if sel_kind == 3 else sel_p, sel_e, sel_t][kind]
		var ids := []
		for i in arr.size():
			if arr[i]:
				ids.append(i)
		for i in ids:
			_twin_set = {i: true}
			_twins(kind, i, 1)
			for j in _twin_set:
				match kind:
					0: pts[j] = true
					1: eds[j] = true
					2: ts[j] = 1
	if pts.is_empty() and eds.is_empty() and not ts.has(1):
		_say("Dissolve: select points, edges or faces first.")
		return
	var t0 := Time.get_ticks_usec()
	var before := _snap()
	var res: Dictionary = em.dissolve(PackedInt32Array(pts.keys()), PackedInt32Array(eds.keys()), ts)
	if not res["ok"]:
		em.restore(before)
		_say("Dissolve: %s - nothing changed." % res["why"])
		return
	_resize_sel()
	sel_p.fill(0)
	sel_e.fill(0)
	sel_t.fill(0)
	sel_pa.fill(0)
	if sel_kind == 2 or sel_kind == 3:
		for k in res["keep"]:
			var e: int = em.edge(k[0], k[1])
			if e >= 0:
				for u in em.poly_tris(em.edge_tris[e * 2]):
					sel_t[u] = 1
		_derive_sel()
	_edit_done("Dissolve", before)
	_update_ui()
	_say("Dissolved: %d faces made, %d points gone (%.1f ms)." % [(res["keep"] as Array).size(), int(res["points"]), (Time.get_ticks_usec() - t0) / 1000.0])


# --- symmetrize topology (Ctrl+Shift+M) ------------------------------------------------

## One side of `axis` rebuilt as the mirror of the other (EditMesh.symmetrize_topology): its
## faces and points, not only their places. `auto`: from the side changed since the two last
## matched (moved, or with points the other hasn't); else `positive` (+ onto -). One undo
## step; the new half selected.
func symmetrize_topology(axis := 0, positive := true, auto := false) -> void:
	if em == null:
		enter_edit(true)
		if em == null:
			return
	knife_cancel()
	_cancel_xf()
	if auto:
		positive = _changed_side(axis)
	var before := _snap()
	var t0 := Time.get_ticks_usec()
	var res: Dictionary = em.symmetrize_topology(axis, positive, -1.0, _bones_twin())
	if not res["ok"]:
		em.restore(before)
		_say("Symmetrize topology: %s." % res["why"])
		return
	_resize_sel()
	select_all(false)
	var keep := sel_kind
	sel_kind = 0
	for p in res["new"]:
		sel_p[p] = 1
	_derive_sel()
	sel_kind = keep
	if keep == 3:
		sel_pa = sel_p.duplicate()
		sel_e.fill(0)
		sel_t.fill(0)
		_derive_sel()
	_edit_done("Symmetrize topology", before)
	_ref_key = ""
	_sym_ref()
	_update_ui()
	_say("Symmetrize topology: %s%s mirrored onto the other side - %d points, %d faces (%.0f ms)." % ["+" if positive else "-", "XYZ"[axis],
		em.points.size(), em.poly_count(), (Time.get_ticks_usec() - t0) / 1000.0])


## The side of `axis` changed since the two last matched (true: +): the one whose points moved
## more, else the one with more points that have no twin on the other side.
func _changed_side(axis: int) -> bool:
	_sym_ref()
	var tol: float = maxf(em.aabb().size.length() * 0.0005, 0.0005)
	var moved := [0.0, 0.0]
	for i in mini(_ref_pts.size(), em.points.size()):
		if absf(_ref_pts[i][axis]) > tol:
			moved[1 if _ref_pts[i][axis] > 0.0 else 0] += (em.points[i] as Vector3).distance_to(_ref_pts[i])
	if moved[0] > 0.0 or moved[1] > 0.0:
		return moved[1] >= moved[0]
	var m: PackedInt32Array = em.mirror_map(axis, tol)
	var lone := [0, 0]
	for i in em.points.size():
		if m[i] < 0 and absf(em.points[i][axis]) > tol:
			lone[1 if em.points[i][axis] > 0.0 else 0] += 1
	return lone[1] >= lone[0]


## Each bone's twin for the mirrored half (a skinned part's binds: .L <-> .R, _L <-> _R,
## Left <-> Right by their names; a bone in the middle its own); empty if not skinned.
func _bones_twin() -> PackedInt32Array:
	var out := PackedInt32Array()
	if part == null or part.skin == null:
		return out
	var sk: Skin = part.skin
	var skel := part.get_node_or_null(part.skeleton) as Skeleton3D
	var names := []
	for i in sk.get_bind_count():
		var nm := str(sk.get_bind_name(i))
		if nm == "" and skel and sk.get_bind_bone(i) >= 0 and sk.get_bind_bone(i) < skel.get_bone_count():
			nm = skel.get_bone_name(sk.get_bind_bone(i))
		names.append(nm)
	for i in names.size():
		var tw := twin_bone_name(names[i])
		var j: int = names.find(tw) if tw != names[i] else i
		out.append(j if j >= 0 else i)
	return out


## The name of a bone's mirror twin (.L <-> .R, _L <-> _R, Left <-> Right, any place in the
## name: "upper.L.001" too); the name itself for a bone in the middle.
static func twin_bone_name(nm: String) -> String:
	for pair in [[".L", ".R"], ["_L", "_R"], [".l", ".r"], ["_l", "_r"], ["Left", "Right"], ["left", "right"]]:
		for k in 2:
			var a: String = pair[k]
			var b: String = pair[1 - k]
			var at := nm.rfind(a)
			if at >= 0 and (at + a.length() == nm.length() or nm[at + a.length()] in [".", "_"]):
				return nm.substr(0, at) + b + nm.substr(at + a.length())
	return nm


# --- binding parts to a character's skeleton (MeshBind) ---------------------------------

const MeshBind := preload("res://scripts/editor/mesh/mesh_bind.gd")
var _bone_pick: OptionButton
var _bones_key := ""


func _build_bind(box: Control) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 2)
	row.add_theme_constant_override("v_separation", 2)
	row.add_child(_btn("Auto-bind to the skeleton", "m_bind_auto", "", "Skins the selected solid to the character's skeleton: each vertex weighted to its nearest\nbones (up to four), so it moves with the animations. Solids added to a character are bound\nlike this by themselves; again after moving one: it's bound where it is now.", func(): bind_part()))
	_bone_pick = OptionButton.new()
	_bone_pick.focus_mode = Control.FOCUS_NONE
	_bone_pick.add_theme_font_size_override("font_size", 14)
	_bone_pick.custom_minimum_size.x = 110
	_bone_pick.tooltip_text = EditorIcons.tip("Bone to bind to", "", "The bone Bind to bone puts the whole solid on, and Solids from bones starts from (Nearest:\nthe bone nearest the selected solid).")
	row.add_child(_bone_pick)
	row.add_child(_btn("Bind to bone", "m_bind_bone", "", "Skins the whole selected solid to the bone picked beside it - it moves rigidly with that\nbone (a helmet on the head, a sword in the hand).", func(): bind_part(null, _picked_bind())))
	row.add_child(_btn("Unbind", "unlock", "", "Lets the selected solid go of the skeleton: it stays where it's drawn now, unanimated\n(a boolean needs it unbound).", func(): unbind_part()))
	_bone_scope = OptionButton.new()
	_bone_scope.focus_mode = Control.FOCUS_NONE
	_bone_scope.add_theme_font_size_override("font_size", 14)
	for s in BONE_SCOPE_LABELS:
		_bone_scope.add_item(s)
	_bone_scope.tooltip_text = EditorIcons.tip("Bones to make solids for", "", "Which bones Solids from bones makes a solid for: the bone picked beside Bind to bone (Nearest:\nthe one nearest the selected solid), that bone and every bone below it, or all the bones.")
	row.add_child(_bone_scope)
	row.add_child(_btn("Solids from bones", "m_bone_parts", "", "Makes a body solid for each bone chosen beside it: a rounded loft from the bone to its child,\nas thick as the body's vertices weighted to that bone (else a share of its length), named after\nthe bone and skinned all to it - it moves with the animations. One undo step.", func(): parts_from_bones()))
	box.add_child(row)


## The model's rig ({} - no skinned part).
func _rig() -> Dictionary:
	return MeshBind.rig_of(parts())


func _can_bind() -> bool:
	return part != null and part.mesh != null and not _rig().is_empty() and _rig()["body"] != part


## The bind picked in the panel (-1: the nearest bone to the part).
func _picked_bind() -> int:
	_fill_bones()
	if _bone_pick == null or _bone_pick.selected <= 0:
		return -2
	return int(_bone_pick.get_item_metadata(_bone_pick.selected))


func _fill_bones() -> void:
	if _bone_pick == null:
		return
	var rig := _rig()
	var key := str(rig.get("skin", null)) + str(rig.get("tpose", false))
	if key == _bones_key:
		return
	_bones_key = key
	_bone_pick.clear()
	_bone_pick.add_item("Nearest")
	_bone_pick.set_item_metadata(0, -2)
	if rig.is_empty():
		_bone_pick.disabled = true
		return
	_bone_pick.disabled = false
	var bs := MeshBind.binds(rig)
	for k in bs.size():
		_bone_pick.add_item(str(bs[k][1]))
		_bone_pick.set_item_metadata(_bone_pick.item_count - 1, k)


## A part's binding as it is: [mesh, skin, skeleton, global transform, its metas].
func _bind_state(p: MeshInstance3D) -> Array:
	var mt := {}
	for k in ["tpose", "tpose_mats", "tpose_skin", "tpose_skel", "bound_part", "mesh_shape", "curve_solid"]:
		if p.has_meta(k):
			mt[k] = p.get_meta(k)
	return [p.mesh, p.skin, p.skeleton, p.global_transform, mt]


func _set_bind_state(p: MeshInstance3D, st: Array) -> void:
	p.mesh = st[0]
	p.skin = st[1]
	p.skeleton = st[2]
	if p.is_inside_tree():
		p.global_transform = st[3]
	for k in ["tpose", "tpose_mats", "tpose_skin", "tpose_skel", "bound_part", "mesh_shape", "curve_solid"]:
		if (st[4] as Dictionary).has(k):
			p.set_meta(k, st[4][k])
		else:
			p.remove_meta(k)


## Every ECurve solid associated with bones (its recipe's "bone": "auto" - its nearest bones, or a skin
## bind's index) bound to them for now - as it's written, so it moves with the animations in the game;
## a converted skinned solid's weights taken from its old mesh, point by nearest point. [[solid, its
## state before]...] - put back after.
func _apply_bone_links() -> Array:
	var out := []
	var rig := _rig()
	for p: MeshInstance3D in parts():
		var spec: Dictionary = p.get_meta("curve_solid", {})
		if not spec.has("bone") or p.mesh == null:
			continue
		var was := _bind_state(p)
		if p.has_meta("weight_src") and p.has_meta("ecurve_skin"):
			var wc: Array = p.get_meta("weighted", [])
			var m: ArrayMesh = wc[1] if wc.size() == 2 and wc[0] == p.mesh else MeshBind.transfer_weights(p.mesh, p.get_meta("weight_src"))
			if m:
				out.append([p, was])
				p.mesh = m
				p.skin = p.get_meta("ecurve_skin")
			continue
		if rig.is_empty() or rig["body"] == p:
			continue
		var b = spec["bone"]
		var st := _bound_state(p, rig, -1 if str(b) == "auto" else int(b))
		(st[4] as Dictionary)["curve_solid"] = spec
		out.append([p, was])
		_set_bind_state(p, st)
	return out


## Part `p` bound to `rig` (bind >= 0: all to that skin bind) - its state after.
func _bound_state(p: MeshInstance3D, rig: Dictionary, bind := -1) -> Array:
	var m := MeshBind.bound_mesh(p, rig, bind)
	var body: MeshInstance3D = rig["body"]
	var skel: Skeleton3D = rig["skel"]
	var path := p.get_path_to(skel)
	var mt := {"bound_part": true}
	if rig["tpose"]:
		mt["tpose"] = true
		mt["tpose_mats"] = body.get_meta("tpose_mats")
		mt["tpose_skin"] = rig["skin"]
		mt["tpose_skel"] = path
		return [m, null, NodePath(""), body.global_transform, mt]
	return [m, rig["skin"], path, body.global_transform, mt]


## Binds part `p` (the selected one) to the character's skeleton - to its nearest bones,
## or (`bind` >= 0) all to that skin bind, -2: the bone nearest it. One undo step.
func bind_part(p: MeshInstance3D = null, bind := -1) -> bool:
	if p == null:
		p = part
	if mode == "edit":
		_leave_edit(true)
	var rig := _rig()
	if p == null or p.mesh == null or rig.is_empty() or rig["body"] == p:
		_say("Bind: select a solid beside a character's skinned body.")
		return false
	if bind == -2:
		bind = MeshBind.nearest_bind(rig, p.global_transform * p.get_aabb().get_center())
	if p.has_meta("curve_solid"):
		# (an ECurve solid: associated with the bones - kept with its recipe, bound as it's saved, so its
		# edits stay free; one undo step)
		var sp0: Dictionary = p.get_meta("curve_solid")
		var sp1: Dictionary = sp0.duplicate()
		sp1["bone"] = "auto" if bind < 0 else bind
		_do("Bones for " + str(p.name), func(): p.set_meta("curve_solid", sp1); _show_part(), func(): p.set_meta("curve_solid", sp0); _show_part())
		_say("%s associated with %s - it moves with the animations once saved." % [p.name, "its nearest bones" if bind < 0 else MeshBind.binds(rig)[bind][1]])
		return true
	var was := _bind_state(p)
	if p.has_meta("bound_part"):   # (bound again: from where it's drawn now)
		_set_bind_state(p, _unbound_state(p, rig))
	var now := _bound_state(p, rig, bind)
	_set_bind_state(p, was)
	_do("Bind " + str(p.name), func(): _set_bind_state(p, now); _fill_parts(); _show_part(); view.request(),
		func(): _set_bind_state(p, was); _fill_parts(); _show_part(); view.request())
	_say("%s bound to %s - it moves with the animations." % [p.name, "the skeleton (its nearest bones)" if bind < 0 else MeshBind.binds(rig)[bind][1]])
	return true


func _unbound_state(p: MeshInstance3D, rig: Dictionary) -> Array:
	var body: MeshInstance3D = rig["body"]
	return [MeshBind.unbound_mesh(p, rig), null, NodePath(""), body.global_transform, {}]


## Lets part `p` (the selected one) go of the skeleton, where it's drawn now. One undo step.
func unbind_part(p: MeshInstance3D = null) -> bool:
	if p == null:
		p = part
	if mode == "edit":
		_leave_edit(true)
	var rig := _rig()
	if p == null or not p.has_meta("bound_part") or rig.is_empty():
		_say("Unbind: select a bound solid.")
		return false
	var was := _bind_state(p)
	var now := _unbound_state(p, rig)
	_do("Unbind " + str(p.name), func(): _set_bind_state(p, now); _fill_parts(); _show_part(); view.request(),
		func(): _set_bind_state(p, was); _fill_parts(); _show_part(); view.request())
	_say("%s unbound: it stays where it is, unanimated." % p.name)
	return true


## A part just added beside a character: bound to its skeleton by itself (once - part of
## the step that added it).
func _bind_new(p: MeshInstance3D) -> void:
	if p.has_meta("bind_tried"):
		return
	p.set_meta("bind_tried", true)
	if p.has_meta("bound_part") or p.mesh == null:
		return
	var rig := _rig()
	if rig.is_empty() or rig["body"] == p:
		return
	if p.has_meta("curve_solid"):
		# (an ECurve solid: associated with its nearest bones - bound as it's saved, its edits free)
		var sp: Dictionary = (p.get_meta("curve_solid") as Dictionary).duplicate()
		sp["bone"] = "auto"
		p.set_meta("curve_solid", sp)
		return
	_set_bind_state(p, _bound_state(p, rig))


# --- parts made from a character's bones (BoneParts) -----------------------------------

const BoneParts := preload("res://scripts/editor/mesh/bone_parts.gd")
const BONE_SCOPE_LABELS := ["This bone", "Bone and children", "All bones"]
var _bone_scope: OptionButton


## The bones Parts from bones makes parts for, as picked in the panel ("bone", "children", "all").
func _picked_bone_scope() -> String:
	if _bone_scope == null or _bone_scope.selected < 0:
		return "bone"
	return BoneParts.SCOPES[_bone_scope.selected]


## Makes a body part for each bone of `scope` ("bone": the one picked in the panel - Nearest:
## the bone nearest the selected part; "children": it and every bone below it; "all": every
## bone; "": as picked in the panel) - a rounded loft along the bone, fitted to the Body's
## vertices weighted to it, named after it and skinned all to it, so it moves with the
## animations. `bind`: a skin bind (-3: the one picked in the panel). One undo step; the parts.
func parts_from_bones(scope := "", bind := -3) -> Array:
	if scope == "":
		scope = _picked_bone_scope()
	if mode == "edit":
		_leave_edit(true)
	var rig := _rig()
	if rig.is_empty() or model == null:
		_say("Solids from bones: open a character with a skeleton.")
		return []
	if bind == -3:
		bind = _picked_bind()
	if bind < 0 and scope != "all":
		if part != null and part != rig["body"] and part.mesh != null:
			bind = MeshBind.nearest_bind(rig, part.global_transform * part.get_aabb().get_center())
		else:
			_say("Solids from bones: pick a bone in the panel (or select a solid beside it).")
			return []
	var mat := MeshIO.default_material()
	mat.resource_name = "Bone solids"
	var made := BoneParts.make(rig, scope, bind, mat)
	if made.is_empty():
		_say("Solids from bones: no bone to make a solid for.")
		return []
	var skel: Skeleton3D = rig["skel"]
	var body: MeshInstance3D = rig["body"]
	var m := model
	var path := NodePath("../" + str(m.get_path_to(skel)))   # (from a part under the model)
	var taken := {}
	for p in parts():
		taken[str(p.name)] = true
	var nodes := []
	for e: Dictionary in made:
		var nm: String = e["name"]
		var i := 2
		while taken.has(nm):
			nm = "%s%d" % [e["name"], i]
			i += 1
		taken[nm] = true
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = e["mesh"]
		mi.set_meta("bind_tried", true)
		mi.set_meta("bound_part", true)
		mi.set_meta("bone_part", e["bone"])
		if rig["tpose"]:
			mi.set_meta("tpose", true)
			mi.set_meta("tpose_mats", body.get_meta("tpose_mats"))
			mi.set_meta("tpose_skin", rig["skin"])
			mi.set_meta("tpose_skel", path)
		else:
			mi.skin = rig["skin"]
			mi.skeleton = path
		nodes.append(mi)
	var at := body.global_transform
	var add := func():
		for mi: MeshInstance3D in nodes:
			m.add_child(mi)
			mi.owner = m
			mi.global_transform = at
		_fill_parts()
		select_part(nodes[0])
	var remove := func():
		for mi: MeshInstance3D in nodes:
			m.remove_child(mi)
		if part in nodes:
			part = null
		_fill_parts()
		_show_part()
		_update_ui()
		view.request()
	_do("Solids from bones", add, remove, nodes)
	_say("%d solid%s made from %s - each skinned to its bone, it moves with the animations." % [nodes.size(), "" if nodes.size() == 1 else "s",
		str(made[0]["bone"]) if scope == "bone" else ("the bones below " + str(made[0]["bone"]) if scope == "children" else "every bone")])
	return nodes


# --- the browsers' and the overview's tooltips: each item's own, the item itself turning in it ------------

## Each list's items' tooltips show the item itself, turning slowly (PinTips' "tip_view": a Mesh or a Node3D
## to copy, or null till it's ready): the models, primitives and materials, the overview's solids and
## collections as they are now. (The lists' own tooltips are on their tabs.)
func _tip_pics() -> void:
	_files.tooltip_text = ""
	_files.set_meta("tip_on_tab", "models")   # (the list's own tooltip: on its tab)
	_files.remove_meta("tip_pic")
	_files.set_meta("tip_view", func(i: int):
		var pth := str(_files.get_item_metadata(i))
		return tip_model(pth))
	var mb = mat_tools.browser if mat_tools else null
	if mb != null and mb.get("list") != null:
		var ml: ItemList = mb.list
		ml.tooltip_text = ""
		ml.set_meta("tip_on_tab", "materials")
		ml.set_meta("tip_view", func(i: int):
			var id := str(ml.get_item_metadata(i))
			var e: Dictionary = mb.lib.entry(id)
			var mat: Material = e["mat"] if e["group"] == "model" else mb.lib.make_material(id)
			var ML: GDScript = load("res://scripts/editor/mesh/material_library.gd")
			return ML.sphere_mesh(ML.sphere_arrays(), mat))
	var pl = get_meta("prims") if has_meta("prims") else null
	var plist: ItemList = (pl as Node).find_child("Primitives", true, false) if pl is Node else null
	if plist:
		plist.tooltip_text = ""
		plist.set_meta("tip_on_tab", "shapes")
		plist.set_meta("tip_view", func(i: int):
			var kind := str(plist.get_item_metadata(i))
			var m: PrimitiveMesh = {"box": BoxMesh.new(), "cylinder": CylinderMesh.new(), "prism": CylinderMesh.new(), "cone": CylinderMesh.new(),
				"sphere": SphereMesh.new(), "torus": TorusMesh.new()}.get(kind, BoxMesh.new())
			if kind == "prism":
				(m as CylinderMesh).radial_segments = 6
			if kind == "cone":
				(m as CylinderMesh).top_radius = 0.0
			m.material = MeshIO.preset(4)
			return m)
	var tr = curve_tools._w("tree") if curve_tools else null
	if tr is Tree:
		(tr as Tree).tooltip_text = ""
		(tr as Tree).auto_tooltip = false   # (Godot's own - the row's name - never over the item's tooltip)
		(tr as Tree).set_meta("tip_fn", func(at: Vector2) -> String: return tree_tip(tr, at))
		(tr as Tree).set_meta("tip_view", func(at: Vector2, probe: bool):
			var it := (tr as Tree).get_item_at_position(at)
			if (tr as Tree).get_button_id_at_position(at) >= 0:
				return false if probe else null   # (its eye or its arrow: that button's tooltip, no picture)
			if it == null or not (it.get_metadata(0) is Dictionary):
				return false if probe else null
			var md: Dictionary = it.get_metadata(0)
			if md.get("part") is MeshInstance3D and is_instance_valid(md["part"]):
				if probe:
					return true
				var p: MeshInstance3D = md["part"]
				if p.mesh == null:
					return null
				var mi := MeshInstance3D.new()
				mi.mesh = p.mesh
				mi.material_override = p.material_override
				return mi
			if md.get("group") is Node3D and is_instance_valid(md["group"]):
				if probe:
					return true
				var g: Node3D = md["group"]
				var root := Node3D.new()
				for q in g.find_children("*", "MeshInstance3D", true, false):
					if (q as MeshInstance3D).mesh != null and (q as Node3D).is_visible_in_tree():
						var mi := MeshInstance3D.new()
						mi.mesh = (q as MeshInstance3D).mesh
						mi.material_override = (q as MeshInstance3D).material_override
						mi.transform = g.global_transform.affine_inverse() * (q as Node3D).global_transform
						root.add_child(mi)
				return root if root.get_child_count() > 0 else null
			return false if probe else null)


## A tree row's (or its button's) tooltip under `at` - for PinTips only: taken from the row the first time it's
## hovered, so Godot's own tooltip never shows beside it.
static func tree_tip(t: Tree, at: Vector2) -> String:
	var it := t.get_item_at_position(at)
	if it == null:
		return ""
	var col := t.get_column_at_position(at)
	var bid := t.get_button_id_at_position(at)
	if bid >= 0 and it.has_meta("btip_%d" % bid):
		return str(it.get_meta("btip_%d" % bid))   # (a button's: kept for PinTips only)
	if bid >= 0 and col >= 0:
		var bi := it.get_button_by_id(col, bid)
		if bi >= 0:
			var key := "btip_%d_%d" % [col, bi]
			var bt := it.get_button_tooltip_text(col, bi)
			if bt != "":
				it.set_meta(key, bt)
				it.set_button_tooltip_text(col, bi, "")
			return str(it.get_meta(key, ""))
	for c in t.columns:
		var tt := it.get_tooltip_text(c)
		if tt != "":
			it.set_meta("tip_%d" % c, tt)
			it.set_tooltip_text(c, "")
	var own := str(it.get_meta("tip_%d" % maxi(col, 0), ""))
	return own if own != "" else str(it.get_meta("tip_0", ""))


## Model `res_path` read for its tooltip (on a worker the first time - null till then; the last few kept).
func tip_model(res_path: String) -> Node3D:
	var c: Dictionary = get_meta("tip_models", {})
	if c.has(res_path):
		var e: Array = c[res_path]
		if e[1] is Node3D:
			return e[1]
		if int(e[0]) >= 0 and WorkerThreadPool.is_task_completed(int(e[0])):
			WorkerThreadPool.wait_for_task_completion(int(e[0]))
			e[0] = -1
			e[1] = (e[2] as Array)[0]
			return e[1] if e[1] is Node3D else null
		return null
	if c.size() >= 6:
		# (the oldest let go - a model read a while ago is read again if it's wanted)
		for k in c.keys():
			var o: Array = c[k]
			if int(o[0]) < 0:
				if o[1] is Node and is_instance_valid(o[1]):
					(o[1] as Node).free()
				c.erase(k)
				break
	var file := EditTarget.read_path(res_path)
	var h := [null]
	var id := WorkerThreadPool.add_task(func(): h[0] = MeshIO.read(file), false, "ECurves: a model for its tooltip")
	c[res_path] = [id, null, h]
	set_meta("tip_models", c)
	return null


# --- the models browser's categories -----------------------------------------------------------------

## [id, label, what it holds] - the models browser's categories.
const MODEL_CATS := [["all", "All", "Every model."],
	["npcs", "NPCs", "The people: each empire's android, the guard, the pirate, Kilon Alios and you."],
	["creatures", "Creatures", "Monsters and animals."],
	["ships", "Ships", "Ships and their hulls."],
	["stations", "Stations", "Space stations."],
	["buildings", "Buildings", "Towns' buildings."],
	["props", "Props", "Everything else - weapons, parts, things."],
	["yours", "Yours", "The models you've made (res://models/ and your mod's)."]]


## Which category model `res_path` is in (MODEL_CATS).
func model_category(res_path: String) -> String:
	var d := res_path.to_lower()
	var n := d.get_file().get_basename()
	if n in ["demon", "skeleton"] or d.contains("creature") or d.contains("monster") or d.contains("fauna"):
		return "creatures"
	if MeshIO.is_character(res_path):
		return "npcs"
	if d.contains("ship") or d.contains("hull"):
		return "ships"
	if d.contains("station"):
		return "stations"
	if d.contains("building") or d.contains("town") or d.contains("house"):
		return "buildings"
	if d.begins_with("res://models/") or d.begins_with("user://"):
		return "yours"
	return "props"


## The category buttons over the models list (made once - an editor made before them gets them too), their
## counts kept up to date; one empty: greyed.
func _model_cats_bar() -> void:
	if _models_box == null:
		return
	var bar := _models_box.get_node_or_null("ModelCats") as HFlowContainer
	if bar == null:
		bar = HFlowContainer.new()
		bar.name = "ModelCats"
		bar.add_theme_constant_override("h_separation", 4)
		bar.add_theme_constant_override("v_separation", 4)
		_models_box.add_child(bar)
		_models_box.move_child(bar, _filter.get_index() + 1)
		for c in MODEL_CATS:
			var b := Button.new()
			b.name = "Cat_" + str(c[0])
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.add_theme_font_size_override("font_size", 14)
			var id := str(c[0])
			b.pressed.connect(func():
				set_meta("model_cat", id)
				_fill_files())
			bar.add_child(b)
	var counts := {"all": _all_files.size()}
	for p in _all_files:
		var k := model_category(p)
		counts[k] = int(counts.get(k, 0)) + 1
	var cat := str(get_meta("model_cat", "all"))
	for c in MODEL_CATS:
		var b := bar.get_node("Cat_" + str(c[0])) as Button
		var n := int(counts.get(c[0], 0))
		b.text = "%s %d" % [c[1], n] if str(c[0]) != "all" else str(c[1])
		b.disabled = n == 0 and str(c[0]) != "all"
		b.set_pressed_no_signal(str(c[0]) == cat)
		b.tooltip_text = EditorIcons.tip("Models: " + str(c[1]), "", str(c[2]) + ("" if n > 0 or str(c[0]) == "all" else "\nNone yet."))

