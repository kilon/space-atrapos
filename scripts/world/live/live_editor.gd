class_name LiveEditor
extends CanvasLayer
## The Live Editor (F10 in a game): everything edited while the game runs. A panel
## down the right of the screen; click anything in the world to pick it (its box
## lit) - a character, a building, a ship, a rock, the ground. Its tabs (plug-ins:
## scripts/world/live/tabs/<id>_tab.gd) show what can be edited on it: Object (where
## it is, its turn and size, its values), Model (its meshes - in the mesh editor),
## Materials (every colour, number and texture of its looks), Animation (its clips
## - in the animation editor), Particles (its effects), Collision (its solids).
## The game goes on underneath (Pause, and the speed, at the top).
##
## Edits apply at once, to every thing of that kind (the panel says which kind:
## LiveEdits' key), and are kept by LiveEdits - put back each time such a thing is
## made - once saved (Save: into the game, or a mod).
##
## A tab (static handles(n), bind(ed), unbind(), live_process(delta), static
## apply_edit(anchor, data)) reaches the editor through: selected, anchor, key,
## cosmos, say(text), edited(section), pick_ray(screen pos), camera(), select(n).

const TABS := ["object", "model", "material", "anim", "fx", "collision"]
const W := 540
const ACCENT := Color(0.55, 0.85, 1.0)
const DIR := "res://scripts/world/live/tabs/"

static var current: LiveEditor

var cosmos: Node
var selected: Node
var anchor: Node
var key := ""
var _panel: PanelContainer
var _title: Label
var _kind: Label
var _status: Label
var _dirty_mark: Label
var _tab_bar: HBoxContainer
var _tab_holder: VBoxContainer
var _parts: OptionButton
var _target: OptionButton
var _pause: Button
var _speed: OptionButton
var _scripts := {}           # tab id -> its script
var _shown: Array = []       # tab ids shown for the selection
var _tab: Control            # the tab showing
var _tab_id := ""
var _box: MeshInstance3D     # the picked thing's box
var _box_mesh: ImmediateMesh
var _mouse_was := Input.MOUSE_MODE_VISIBLE
var _tri := {}               # mesh -> TriangleMesh (picking)

static var _box_mat: StandardMaterial3D


## Opens the Live Editor over game `c` (Cosmos), or closes it.
static func toggle(c: Node) -> void:
	if current and is_instance_valid(current):
		current.close()
		return
	var e := LiveEditor.new()
	e.cosmos = c
	c.add_child(e)


func _ready() -> void:
	current = self
	layer = 45   # (under the dialogs - UI.confirm / choice, 50)
	process_mode = Node.PROCESS_MODE_ALWAYS
	LiveEdits.hook(get_tree())
	for id in TABS:
		var p: String = DIR + id + "_tab.gd"
		if ResourceLoader.exists(p):
			var sc = load(p)
			if sc is GDScript and LiveEdits.has_static(sc, "handles"):   # (a tab that doesn't compile is left out)
				_scripts[id] = sc
	_build()
	PinTips.install(self, "live")   # (the editor screens' tooltips)
	_mouse_was = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_box_mesh = ImmediateMesh.new()
	_box = MeshInstance3D.new()
	_box.mesh = _box_mesh
	_box.material_override = box_material()
	_box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_box.top_level = true
	add_child(_box)
	say("Click anything in the world to pick it. The game goes on - Pause at the top.")


## The selection box's look (unshaded lines over everything: CosmosWarm warms it).
static func box_material() -> StandardMaterial3D:
	if _box_mat == null:
		_box_mat = StandardMaterial3D.new()
		_box_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_box_mat.vertex_color_use_as_albedo = true
		_box_mat.no_depth_test = true
		_box_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_box_mat.render_priority = 10
	return _box_mat


func close() -> void:
	if LiveEdits.dirty and is_inside_tree():
		UI.choice(self, "LIVE EDITS", "Your edits aren't saved (into %s). Unsaved, they last till the game closes." % EditTarget.label(), [
			["Keep editing", Callable()],
			["Close", _close_now],
			["Save and close", func(): save(); _close_now()],
		])
		return
	_close_now()


func _close_now() -> void:
	_unbind()
	if selected and is_instance_valid(selected):
		SelectOutline.show(selected, false)
	get_tree().paused = false
	Engine.time_scale = 1.0
	Input.mouse_mode = _mouse_was
	if current == self:
		current = null
	queue_free()


func _exit_tree() -> void:
	if current == self:
		current = null
		Engine.time_scale = 1.0


# --- The panel -----------------------------------------------------------------------

func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.name = "LivePanel"
	_panel.add_theme_stylebox_override("panel", UI.panel_style(ACCENT))
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -W - 12
	_panel.offset_right = -12
	_panel.offset_top = 12
	_panel.offset_bottom = -12
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # (wider content: it grows into the screen, not off it)
	root.add_child(_panel)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	_panel.add_child(m)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	m.add_child(box)
	# The header: the title, pause, speed, save, close.
	var h := HBoxContainer.new()
	h.add_child(UI.label("LIVE EDITOR", 20, ACCENT))
	_dirty_mark = UI.label("", 14, Color(1.0, 0.75, 0.4))
	_dirty_mark.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_dirty_mark)
	h.add_child(_btn("", "close", "Close (F10)", "Closes the Live Editor; the game goes on.", close))
	box.add_child(h)
	var h2 := HBoxContainer.new()
	_pause = _btn("Pause", "stop", "Pause (P with the panel's focus off)", "Stops the game's time - the editor goes on.", func():
		set_paused(not get_tree().paused))
	_pause.toggle_mode = true
	h2.add_child(_pause)
	_speed = OptionButton.new()
	_speed.focus_mode = Control.FOCUS_NONE
	for s in [0.1, 0.25, 0.5, 1.0, 2.0]:
		_speed.add_item("%sx" % s)
		_speed.set_item_metadata(_speed.item_count - 1, s)
	_speed.select(3)
	_speed.tooltip_text = "The game's speed."
	_speed.item_selected.connect(func(i): Engine.time_scale = float(_speed.get_item_metadata(i)))
	h2.add_child(_speed)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h2.add_child(gap)
	h2.add_child(_btn("Save", "save", "Ctrl+S", "Keeps every edit: put back each time such a thing is made.", save))
	box.add_child(h2)
	var h4 := HBoxContainer.new()
	h4.add_child(UI.label("Save", 14, UI.TEXT_DIM))
	_target = OptionButton.new()
	_target.focus_mode = Control.FOCUS_NONE
	_target.clip_text = true
	_target.custom_minimum_size.x = 120
	_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_target.tooltip_text = "Where Save keeps the edits: the game itself, or one of your mods."
	_target.item_selected.connect(func(i): EditTarget.mod_id = str(_target.get_item_metadata(i)))
	h4.add_child(_target)
	_fill_targets()
	box.add_child(h4)
	box.add_child(HSeparator.new())
	# The selection: its name, its kind (what an edit applies to), its parts.
	_title = UI.label("Nothing picked", 18, NeonTheme.HEAD)
	_title.clip_text = true
	box.add_child(_title)
	_kind = UI.label("", 14, UI.TEXT_DIM)
	_kind.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_kind)
	var h3 := HBoxContainer.new()
	h3.add_child(_btn("Up", "up", "", "Picks what this is part of.", func():
		if selected and selected.get_parent() and selected.get_parent() != cosmos:
			select(selected.get_parent())))
	_parts = OptionButton.new()
	_parts.focus_mode = Control.FOCUS_NONE
	_parts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_parts.clip_text = true
	_parts.tooltip_text = "Its parts: pick one."
	_parts.item_selected.connect(func(i):
		var n = instance_from_id(int(_parts.get_item_metadata(i))) if _parts.get_item_metadata(i) else null
		if n is Node:
			select(n))
	h3.add_child(_parts)
	box.add_child(h3)
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 2)
	box.add_child(_tab_bar)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_tab_holder = VBoxContainer.new()
	_tab_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_tab_holder)
	_status = UI.label("", 14, UI.TEXT_DIM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


func _fill_targets() -> void:
	_target.clear()
	_target.add_item("into the game" if EditTarget.game_writable() else "(game: read-only)")
	_target.set_item_metadata(0, "")
	for m in Mods.installed():
		_target.add_item("into mod: " + str(m["name"]))
		_target.set_item_metadata(_target.item_count - 1, m["id"])
		if m["id"] == EditTarget.mod_id:
			_target.select(_target.item_count - 1)


func _btn(text: String, icon: String, keys: String, help: String, cb: Callable) -> Button:
	var b := UI.button(text, cb, 14)
	b.focus_mode = Control.FOCUS_NONE
	EditorIcons.dress(b, icon, EditorIcons.tip(text if text != "" else keys, keys, help))
	b.text = text
	return b


func set_paused(on: bool) -> void:
	get_tree().paused = on
	_pause.set_pressed_no_signal(on)
	_pause.text = "Paused" if on else "Pause"


func say(t: String) -> void:
	if _status:
		_status.text = t


## A tab changed something (section `sec` of the selection's kind): kept, to save,
## and - a moment later - put on every other thing of that kind in the world too.
func edited(_sec := "") -> void:
	if key != "":
		LiveEdits.touched(key)
		_spread_t = 0.3
	_dirty_mark.text = "  ● unsaved"


var _spread_t := -1.0


## The selection's kind's edits put on every thing of that kind in the world now.
func apply_everywhere() -> int:
	if key == "":
		return 0
	var n := 0
	var stack: Array = [cosmos]
	while not stack.is_empty():
		var x: Node = stack.pop_back()
		if x == self:
			continue
		var k := ""
		if x.has_meta("edit_key"):
			k = str(x.get_meta("edit_key"))
		elif x.scene_file_path != "":
			k = x.scene_file_path
		elif x.get_script() and (x.get_script() as Script).resource_path == key:
			k = key
		if k == key and x != anchor:
			LiveEdits.apply(x, key)
			n += 1
		for c in x.get_children():
			stack.append(c)
	return n


## A Talos tool (`id`: "mesh", "anim", "fx") in a window over the running game: the
## tool, embedded, under a bar of `buttons` ([[label, icon, help, Callable(tool)]]).
func open_tool(id: String, title: String, buttons: Array = []) -> Node:
	var w := Window.new()
	w.title = title
	w.size = Vector2i(1500, 860)
	w.process_mode = Node.PROCESS_MODE_ALWAYS
	w.wrap_controls = false
	w.transient = true
	add_child(w)
	var bg := Panel.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	w.add_child(box)
	var bar := HBoxContainer.new()
	box.add_child(bar)
	var t: Node = load(TalosNav.SCENES[id]).instantiate()
	t.set("embedded", true)
	for b in buttons:
		var cb: Callable = b[3]
		bar.add_child(_btn(b[0], b[1], "", b[2], func(): cb.call(t)))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	var close_it := func():
		if t.get("dirty") == true and t.has_method("guard"):
			t.guard(w.queue_free)
		else:
			w.queue_free()
	bar.add_child(_btn("Close", "close", "", "Closes the window (asks about unsaved work).", close_it))
	w.close_requested.connect(close_it)
	if t is Control:
		t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(t)
	w.popup_centered()
	return t


func save() -> void:
	if _tab and _tab.has_method("save"):
		_tab.save()
	if LiveEdits.save():
		_dirty_mark.text = ""
		say("Saved into %s - put back each time such a thing is made." % EditTarget.label())
	else:
		say("Can't save into %s: pick a mod (top right)." % EditTarget.label())


# --- Picking -------------------------------------------------------------------------

func camera() -> Camera3D:
	return get_viewport().get_camera_3d()


## The ray under screen point `p` (global): [origin, direction].
func pick_ray(p: Vector2) -> Array:
	var cam := camera()
	if cam == null:
		return [Vector3.ZERO, Vector3.FORWARD]
	return [cam.project_ray_origin(p), cam.project_ray_normal(p)]


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		if Keybinds.pressed(event, "live_edit") or (k.keycode == KEY_ESCAPE and not _has_dialog()):
			get_viewport().set_input_as_handled()
			close()
			return
		if k.ctrl_pressed and k.keycode == KEY_S:
			get_viewport().set_input_as_handled()
			save()
			return
		if k.keycode == KEY_F1:
			get_viewport().set_input_as_handled()
			EditorDocs.open(_panel, "live", EditorDocs.FILE)
			return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if _panel.get_global_rect().has_point(mb.position) or _has_dialog() or _over_gui(mb.position):
		return
	get_viewport().set_input_as_handled()
	var r := pick_ray(mb.position)
	if _tab and _tab.has_method("pick_in_world") and _tab.pick_in_world(r[0], r[1]):
		return
	var hit := pick(r[0], r[1])
	if hit:
		select(hit)
	else:
		say("Nothing there.")


func _has_dialog() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit


## A control (a dialog, its dimmed backdrop, the HUD's buttons) under `p` takes the
## click - not a full-screen holder letting clicks through.
func _over_gui(p: Vector2) -> bool:
	var c := get_viewport().gui_get_hovered_control()
	if c == null or not c.is_visible_in_tree() or c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		return false
	var full := c.get_global_rect().size.is_equal_approx(get_viewport().get_visible_rect().size)
	return not full or c is ColorRect


## What a ray first meets in the game's world: the nearest drawn thing (its mesh's
## triangles; a scatter of many - flora, rocks - as a whole) - or null.
func pick(o: Vector3, d: Vector3) -> Node:
	var best: Node = null
	var bd := INF
	var stack: Array = [cosmos]
	var cam := camera()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n == self or n == cam:
			continue
		if n is Node3D and not (n as Node3D).visible:
			continue
		if n is CanvasItem or n is CanvasLayer or n is Viewport:
			continue
		for c in n.get_children():
			stack.append(c)
		if not n is GeometryInstance3D:
			continue
		var gi := n as GeometryInstance3D
		var aabb := gi.global_transform * gi.get_aabb()
		if aabb.size.length() > 400.0 and aabb.has_point(o):
			continue   # (a sky, an atmosphere, the sea round you)
		var at = aabb.intersects_ray(o, d)
		if at == null and not aabb.has_point(o):
			continue
		var dist := (o - (at as Vector3)).length() if at != null else 0.0
		if dist > bd:
			continue
		if gi is MeshInstance3D and (gi as MeshInstance3D).mesh:
			var tm := _triangles((gi as MeshInstance3D).mesh)
			if tm:
				var inv := gi.global_transform.affine_inverse()
				var res := tm.intersect_ray(inv * o, (inv.basis * d).normalized())
				if res.is_empty():
					continue
				dist = (gi.global_transform * Vector3(res["position"]) - o).length()
		if dist < bd:
			bd = dist
			best = gi
	return best


func _triangles(m: Mesh) -> TriangleMesh:
	if _tri.has(m):
		return _tri[m]
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s) if m is ArrayMesh else []
		n += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() if a.size() > 0 and a[Mesh.ARRAY_VERTEX] != null else 0
	var tm: TriangleMesh = m.generate_triangle_mesh() if n < 400000 else null
	_tri[m] = tm
	return tm


# --- The selection --------------------------------------------------------------------

func select(n: Node) -> void:
	_unbind()
	if selected and is_instance_valid(selected):
		SelectOutline.show(selected, false)
	selected = n
	SelectOutline.show(n, true)   # (outlined - and its box drawn)
	var a := LiveEdits.anchor_of(n)
	anchor = a[0]
	key = a[1]
	_title.text = _name_of(n)
	_kind.text = ("Edits apply to %s." % kind_name(key)) if key != "" else "Not part of anything kept: edits last till it's gone."
	_fill_parts()
	_shown.clear()
	UI.clear(_tab_bar)
	for id in TABS:
		var s = _scripts.get(id)
		if s and s.handles(n):
			_shown.append(id)
			var b := _btn(str(s.TITLE), str(s.ICON), "", "The %s of what's picked." % str(s.TITLE).to_lower(), show_tab.bind(id))
			b.name = "Tab_" + id
			b.toggle_mode = true
			_tab_bar.add_child(b)
	if _shown.is_empty():
		say("Nothing here to edit.")
		return
	show_tab(_tab_id if _tab_id in _shown else _shown[0])


func show_tab(id: String) -> void:
	_unbind()
	_tab_id = id
	for b in _tab_bar.get_children():
		(b as Button).set_pressed_no_signal(b.name == "Tab_" + id)
	_tab = _scripts[id].new()
	_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_holder.add_child(_tab)
	_tab.bind(self)


## The tab showing now (its id "" - none).
func tab() -> Control:
	return _tab


func _unbind() -> void:
	if _tab and is_instance_valid(_tab):
		_tab.unbind()
		_tab.queue_free()
	_tab = null


func _fill_parts() -> void:
	_parts.clear()
	_parts.add_item("(its parts)")
	_parts.set_item_metadata(0, null)
	if selected == null:
		return
	var k := 0
	for c in selected.get_children():
		if c is Node3D and k < 60:
			_parts.add_item(_name_of(c))
			_parts.set_item_metadata(_parts.item_count - 1, c.get_instance_id())
			k += 1


static func _name_of(n: Node) -> String:
	var s := str(n.name)
	if s.contains("@"):
		s = n.get_class()
	if n.has_meta("model_id"):
		s += "  (%s)" % n.get_meta("model_id")
	return s


## What a key stands for, in words: "every Cosmos Creature", "every town: athens port".
static func kind_name(k: String) -> String:
	if k.begins_with("res://"):
		return "every " + k.get_file().get_basename().capitalize()
	if k.contains("/"):
		var parts := k.split("/")
		return "every %s: %s" % [parts[0], " ".join(parts.slice(1))]
	return "every " + k


func _process(delta: float) -> void:
	if selected and not is_instance_valid(selected):
		_unbind()
		selected = null
		_title.text = "Gone"
		UI.clear(_tab_bar)
	if _tab and _tab.has_method("live_process"):
		_tab.live_process(delta)
	if _spread_t > 0.0:
		_spread_t -= delta / maxf(Engine.time_scale, 0.01)
		if _spread_t <= 0.0:
			apply_everywhere()
	_draw_box()


func _draw_box() -> void:
	_box_mesh.clear_surfaces()
	if selected == null or not selected is Node3D or not (selected as Node3D).is_inside_tree():
		return
	var aabb := _aabb_of(selected)
	if aabb.size == Vector3.ZERO:
		return
	_box_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_box_mesh.surface_set_color(Color(ACCENT, 0.9))
	var p := aabb.position
	var s := aabb.size
	var c := [p, p + Vector3(s.x, 0, 0), p + Vector3(s.x, 0, s.z), p + Vector3(0, 0, s.z)]
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		for y in [0.0, s.y]:
			_box_mesh.surface_add_vertex(a + Vector3(0, y, 0))
			_box_mesh.surface_add_vertex(b + Vector3(0, y, 0))
		_box_mesh.surface_add_vertex(a)
		_box_mesh.surface_add_vertex(a + Vector3(0, s.y, 0))
	_box_mesh.surface_end()


## `n`'s box (global): its own drawn box, or its drawn parts' together.
func _aabb_of(n: Node) -> AABB:
	if n is VisualInstance3D:
		return (n as VisualInstance3D).global_transform * (n as VisualInstance3D).get_aabb()
	var out := AABB()
	var first := true
	var k := 0
	for c in n.find_children("*", "VisualInstance3D", true, false):
		var b: AABB = (c as VisualInstance3D).global_transform * (c as VisualInstance3D).get_aabb()
		out = b if first else out.merge(b)
		first = false
		k += 1
		if k > 200:
			break
	if first and n is Node3D:
		return AABB((n as Node3D).global_position - Vector3.ONE * 0.5, Vector3.ONE)
	return out
