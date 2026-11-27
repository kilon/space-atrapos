extends Control
## Talos's animation editor (Talos > Animation, F7): a character's clips on a
## timeline. Pick a character (every model Stage3D has) and a clip; play, scrub
## and step it; pose its bones in a 3D view (click a bone, R to turn it - X / Y /
## Z lock the axis - G to move it, or type the angles) and key them (K: the
## bone, Shift+K: every bone); a dope sheet shows each bone's keys along time -
## select, drag, copy, paste and delete them. New clips (empty or copies), your
## own renamed or deleted; length and loop set. Save (Ctrl+S) writes each
## changed clip as an Animation resource, art/<id>_3d/clips/<clip>.tres, through
## EditTarget (the game, or the mod the Mod Editor is on) - Stage3D.use_clips puts
## those files in the models' libraries wherever the game's characters get
## their clips (replacing the model's clip of that name, or adding one).
##
## The edits are kept per character as a document: {clips: name -> Animation,
## order, base (the model's own clip names), files (names with a file now),
## changed, removed}. Animations in a document are never changed in place
## once an undo step holds them: an edit works on a copy (_writable) - so an
## undo step is just the document's dictionaries copied (cheap), and the
## model's own clips (shared with the game) are never touched.
## Playback doesn't use the AnimationPlayer: the clip is sampled as Godot
## samples it (position / rotation / scale track interpolation - rotations
## slerped) straight onto the skeleton, so the edited copy shows at once.
## The view draws only when something changed (or while playing).

const ACCENT := Color(1.0, 0.62, 0.3)
const FS := 13                         # code-drawn text (px)
const RULER_H := 24.0
const ROW_H := 20.0
const NAME_W := 128.0
const UNDO_MAX := 200
const SPEEDS := [0.1, 0.25, 0.5, 1.0, 2.0]
const ONION := [-4, -2, 2, 4]          # onion skin: ghost poses this many frames off
const HIDE_MIN := ["MIN_Bow", "MIN_Axe"]   # (the Minoan body's other weapons: as the game's rifle-carriers)

## Set before it enters the tree (the Mod Editor embeds it): no rail, Esc doesn't leave.
var embedded := false
## Unsaved edits (any character's).
var dirty := false

## The character showing, its clip, the frame.
var char_id := ""
var clip := ""
var frame := 0
var time := 0.0
var playing := false
var loop_play := true
var speed := 1.0
var onion := false
var auto_key := false
## The selected bone (-1: none) and keys (Vector2i(bone, frame) -> true).
var bone := -1
var sel_keys := {}
## The pose shown but not keyed yet: bone -> {"rot": Quaternion, "pos": Vector3} (this frame only).
var pose := {}
## What Ctrl+C took: {kind: "keys", items: [...]} or {kind: "pose", bones: {...}}.
var clipboard := {}

var _docs := {}                        # character id -> its document
var _fresh: Animation = null           # the copy this edit works on (_writable)
var _loading := ""                     # a model loading on a worker
var _fps := 30.0
var _prefix := "Rig/Skeleton3D"        # the tracks' path to the skeleton
var _rows: Array = []                  # per bone: PackedInt32Array of its key frames
var _children: Array = []              # per bone: its child bones
var _modal := {}                       # R / G: {kind, axis, start, rot, pos}
var _drag := ""                        # the view: "orbit" / "pan"
var _built := false

# The view.
var _vp: SubViewport
var _cam: Camera3D
var _view: Control
var _model: Node3D
var _sk: Skeleton3D
var _ap: AnimationPlayer
var yaw := 0.5
var pitch := 0.12
var dist := 3.4
var target := Vector3(0, 0.95, 0)

# The panels.
var _note: Label
var _save_btn: Button
var _undo_btn: Button
var _redo_btn: Button
var _chars: OptionButton
var _clip_list: ItemList
var _name_edit: LineEdit
var _len_spin: SpinBox
var _loop_check: CheckBox
var _del_btn: Button
var _play_btn: Button
var _frame_label: Label
var _speed_opt: OptionButton
var _loop_play_check: CheckBox
var _onion_check: CheckBox
var _bone_label: Label
var _rot: Array = []                   # SpinBoxes: x, y, z (degrees)
var _pos: Array = []                   # SpinBoxes: x, y, z (m)
var _interp: OptionButton
var _sheet: Sheet
var _syncing := false


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build()
	open_character("player" if Stage3D.has_model("player") else (characters()[0] if not characters().is_empty() else ""))


## Every character with a model (art/<id>_3d/).
static func characters() -> Array:
	var out: Array = []
	for dir in DirAccess.get_directories_at("res://art"):
		if dir.ends_with("_3d") and Stage3D.has_model(dir.trim_suffix("_3d")):
			out.append(dir.trim_suffix("_3d"))
	out.sort()
	return out


# --- The screen ------------------------------------------------------------------

func _build() -> void:
	var col: VBoxContainer
	if embedded:
		col = VBoxContainer.new()
		col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		col.add_theme_constant_override("separation", 8)
		add_child(col)
	else:
		col = TalosNav.wrap(UI.modal(self, ACCENT, Vector2.ZERO, true), "anim", func(id): TalosNav.go(get_tree(), id, guard))
	var hd: Array = TalosNav.header("ANIMATION", "", ACCENT)
	var header: HBoxContainer = hd[0]
	_note = hd[1]
	_save_btn = _btn("Save", "save", "Ctrl+S", "Writes every changed clip as art/<id>_3d/clips/<clip>.tres - into the game,\nor into your mod in the Mod Editor. The game uses them in place of the model's clips.", save)
	header.add_child(_save_btn)
	_undo_btn = _btn("Undo", "undo", "Ctrl+Z", "Takes back the last edit.", undo)
	header.add_child(_undo_btn)
	_redo_btn = _btn("Redo", "redo", "Ctrl+Shift+Z", "Does again what Undo took back.", redo)
	header.add_child(_redo_btn)
	header.add_child(EditorIcons.docs_button(self, "anim"))
	col.add_child(header)

	var split := VSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(split)
	var top := HBoxContainer.new()
	top.size_flags_vertical = SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 10)
	split.add_child(top)
	top.add_child(_build_clips())
	top.add_child(_build_view())
	top.add_child(_build_pose())
	split.add_child(_build_timeline())
	if not embedded:
		UI.scale_fonts(col, "menu", 1.2)
	_built = true
	_refresh_header()


func _build_clips() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 250
	box.add_theme_constant_override("separation", 6)
	box.add_child(UI.section("CHARACTER"))
	_chars = OptionButton.new()
	_chars.focus_mode = FOCUS_NONE
	_chars.tooltip_text = EditorIcons.tip("Character", "", "Whose clips to edit: every character with a 3D model.")
	for id in characters():
		_chars.add_item(id)
	_chars.item_selected.connect(func(i): open_character(_chars.get_item_text(i)))
	box.add_child(_chars)
	box.add_child(UI.section("CLIPS"))
	_clip_list = ItemList.new()
	_clip_list.size_flags_vertical = SIZE_EXPAND_FILL
	_clip_list.focus_mode = FOCUS_NONE
	_clip_list.add_theme_font_size_override("font_size", 14)
	_clip_list.tooltip_text = EditorIcons.tip("Clips", "", "The character's clips: frames, loop. * unsaved changes; [own] a clip of yours;\n[file] the model's clip replaced by a saved one.")
	_clip_list.item_selected.connect(func(i): select_clip(str(_clip_list.get_item_metadata(i))))
	box.add_child(_clip_list)
	var row := HBoxContainer.new()
	row.add_child(_btn("New clip", "new", "", "A new empty clip of your own (the rest pose till you key it).", func(): new_clip(false)))
	row.add_child(_btn("Duplicate", "duplicate", "", "A copy of the selected clip, to change as a clip of your own.", func(): new_clip(true)))
	_del_btn = _btn("Delete clip", "delete", "", "Your own clip: deletes it. The model's clip with a saved file: back to the model's own.", delete_clip)
	row.add_child(_del_btn)
	box.add_child(row)
	var g := GridContainer.new()
	g.columns = 2
	g.add_child(UI.label("Name", 14, UI.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.tooltip_text = EditorIcons.tip("Rename", "Enter", "Your own clips only (the model's clip names stay: the game plays them by name).")
	_name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(t): rename_clip(t); _name_edit.release_focus())
	g.add_child(_name_edit)
	g.add_child(UI.label("Frames", 14, UI.TEXT_DIM))
	_len_spin = SpinBox.new()
	_len_spin.min_value = 2
	_len_spin.max_value = 900
	_len_spin.tooltip_text = EditorIcons.tip("Length", "", "The clip's length in frames (30 a second). Keys past the end are kept, unplayed.")
	_len_spin.value_changed.connect(func(v): if not _syncing: set_length(int(v)))
	g.add_child(_len_spin)
	g.add_child(UI.label("Loop", 14, UI.TEXT_DIM))
	_loop_check = CheckBox.new()
	_loop_check.focus_mode = FOCUS_NONE
	_loop_check.tooltip_text = EditorIcons.tip("Loop", "", "The clip loops in the game (its last frame blends into its first).")
	_loop_check.toggled.connect(func(on): if not _syncing: set_loop(on))
	g.add_child(_loop_check)
	box.add_child(g)
	return box


func _build_view() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_child(_btn("Front view", "eye", "Numpad 1", "Looks at the character from the front.", func(): view("front")))
	row.add_child(_btn("Side view", "eye", "Numpad 3", "From its left side.", func(): view("side")))
	row.add_child(_btn("Top view", "eye", "Numpad 7", "From above.", func(): view("top")))
	var hint := UI.label("", 14, UI.TEXT_DIM)
	hint.text = "click a bone - R turn, G move (X/Y/Z axis) - right-drag orbit, middle-drag pan, wheel zoom"
	hint.clip_text = true
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(hint)
	box.add_child(row)
	var holder := Control.new()
	holder.size_flags_vertical = SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(320, 240)
	holder.clip_contents = true
	box.add_child(holder)
	var vpc := SubViewportContainer.new()
	vpc.stretch = true
	vpc.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vpc.mouse_filter = MOUSE_FILTER_IGNORE
	holder.add_child(vpc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.positional_shadow_atlas_size = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vpc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.05, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_BG
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()     # (the key light: upper left, toward the front)
	key.light_energy = 1.6
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 12.0
	_vp.add_child(key)
	key.look_at_from_position(Vector3(-3.4, 4.0, 3.0), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()     # (a cool rim from behind: the metal's edges)
	rim.light_energy = 0.7
	rim.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(rim)
	rim.look_at_from_position(Vector3(2.5, 2.0, -3.5), Vector3.ZERO, Vector3.UP)
	_vp.add_child(_grid())
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.05
	_cam.far = 100.0
	_vp.add_child(_cam)
	_view = Overlay.new()
	(_view as Overlay).ed = self
	_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_view.mouse_filter = MOUSE_FILTER_STOP
	_view.focus_mode = FOCUS_CLICK
	holder.add_child(_view)
	_aim()
	return box


## The ground grid: 4 x 4 m, a line each 25 cm, the axes brighter.
func _grid() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in range(-8, 9):
		var c := Color(0.5, 0.55, 0.65, 0.55) if i == 0 else (Color(0.4, 0.42, 0.5, 0.35) if i % 4 == 0 else Color(0.35, 0.37, 0.45, 0.18))
		var x := i * 0.25
		for seg in [[Vector3(x, 0, -2), Vector3(x, 0, 2)], [Vector3(-2, 0, x), Vector3(2, 0, x)]]:
			st.set_color(c)
			st.add_vertex(seg[0])
			st.set_color(c)
			st.add_vertex(seg[1])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _build_pose() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 250
	box.add_theme_constant_override("separation", 6)
	box.add_child(UI.section("BONE"))
	_bone_label = UI.label("(click a bone)", 16, NeonTheme.TEXT)
	box.add_child(_bone_label)
	box.add_child(UI.label("Rotation (degrees)", 14, UI.TEXT_DIM))
	_rot = _vec_fields(box, -360.0, 360.0, 0.1, func(): _fields_changed("rot"), "Rotation", "The bone's turn from its parent, as X, Y, Z angles (Y, then X, then Z).\nTyping one poses the bone; K keys it (or turn Auto-key on).")
	box.add_child(UI.label("Position (m)", 14, UI.TEXT_DIM))
	_pos = _vec_fields(box, -10.0, 10.0, 0.001, func(): _fields_changed("pos"), "Position", "The bone's place from its parent (the pelvis: the body's height and sway).\nK keys it.")
	var row := HBoxContainer.new()
	row.add_child(UI.label("Easing", 14, UI.TEXT_DIM))
	_interp = OptionButton.new()
	_interp.focus_mode = FOCUS_NONE
	for t in ["Linear", "Smooth", "Step"]:
		_interp.add_item(t)
	_interp.tooltip_text = EditorIcons.tip("Easing", "", "How this bone moves between its keys in this clip: Linear (turns slerped, as the game\nalways did), Smooth (cubic: eases through the keys) or Step (holds each key).")
	_interp.item_selected.connect(func(i): set_interpolation(i))
	_interp.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_interp)
	box.add_child(row)
	var keys := HBoxContainer.new()
	keys.add_child(_btn("Key bone", "key", "K", "Keys the selected bone's pose at this frame.", func(): key_bone()))
	keys.add_child(_btn("Key all", "keypose", "Shift+K", "Keys every bone's pose at this frame.", func(): key_all()))
	box.add_child(keys)
	var keys2 := HBoxContainer.new()
	keys2.add_child(_btn("Reset pose", "reload", "Alt+R", "Drops the pose not keyed yet (back to the clip's).", func(): clear_pose()))
	keys2.add_child(_btn("Rest pose", "restart", "", "Poses the selected bone as it rests (not keyed till K).", rest_bone))
	box.add_child(keys2)
	var auto := CheckBox.new()
	auto.text = "Auto-key"
	auto.focus_mode = FOCUS_NONE
	auto.tooltip_text = EditorIcons.tip("Auto-key", "", "Every pose you give a bone is keyed at once (no K needed).")
	auto.toggled.connect(func(on): auto_key = on)
	box.add_child(auto)
	return box


func _vec_fields(parent: Control, lo: float, hi: float, step: float, changed: Callable, what: String, help: String) -> Array:
	var row := HBoxContainer.new()
	var out: Array = []
	for i in 3:
		var s := SpinBox.new()
		s.min_value = lo
		s.max_value = hi
		s.step = step
		s.prefix = "XYZ"[i]
		s.size_flags_horizontal = SIZE_EXPAND_FILL
		s.custom_minimum_size.x = 76
		s.tooltip_text = EditorIcons.tip(what + " " + "XYZ"[i], "", help)
		s.value_changed.connect(func(_v): if not _syncing: changed.call())
		row.add_child(s)
		out.append(s)
	parent.add_child(row)
	return out


func _build_timeline() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.y = 230
	box.add_theme_constant_override("separation", 4)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	_play_btn = _btn("Play", "play", "Space", "Plays the clip (again: pauses).", toggle_play)
	bar.add_child(_play_btn)
	bar.add_child(_btn("Previous frame", "back", "Left", "One frame back.", func(): step(-1)))
	bar.add_child(_btn("Next frame", "forward", "Right", "One frame on.", func(): step(1)))
	bar.add_child(_btn("Previous key", "prevkey", "Ctrl+Left", "To the selected bone's key before (any bone's, with none selected).", func(): jump_key(-1)))
	bar.add_child(_btn("Next key", "nextkey", "Ctrl+Right", "To the next key.", func(): jump_key(1)))
	_frame_label = UI.label("0 / 0", 16, ACCENT)
	_frame_label.custom_minimum_size.x = 96
	_frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_frame_label)
	var lp := CheckBox.new()
	lp.text = "Loop"
	lp.button_pressed = true
	lp.focus_mode = FOCUS_NONE
	lp.tooltip_text = EditorIcons.tip("Loop playback", "L", "Playing goes round and round (off: stops at the end).")
	lp.toggled.connect(func(on): loop_play = on)
	bar.add_child(lp)
	_loop_play_check = lp
	_speed_opt = OptionButton.new()
	_speed_opt.focus_mode = FOCUS_NONE
	for s in SPEEDS:
		_speed_opt.add_item("%sx" % str(s))
	_speed_opt.select(SPEEDS.find(1.0))
	_speed_opt.tooltip_text = EditorIcons.tip("Speed", "", "Playback speed.")
	_speed_opt.item_selected.connect(func(i): speed = SPEEDS[i])
	bar.add_child(_speed_opt)
	var on := CheckBox.new()
	on.text = "Onion"
	on.focus_mode = FOCUS_NONE
	on.tooltip_text = EditorIcons.tip("Onion skin", "O", "Ghost skeletons 2 and 4 frames before (blue) and after (amber).")
	on.toggled.connect(func(v): onion = v; _redraw())
	bar.add_child(on)
	_onion_check = on
	var gap := Control.new()
	gap.size_flags_horizontal = SIZE_EXPAND_FILL
	bar.add_child(gap)
	bar.add_child(_btn("Copy keys", "duplicate", "Ctrl+C", "Copies the selected keys (none selected: the whole pose at this frame).", copy))
	bar.add_child(_btn("Copy pose", "keypose", "Ctrl+Shift+C", "Copies every bone's pose at this frame.", copy_pose))
	bar.add_child(_btn("Paste", "paste", "Ctrl+V", "Pastes the keys or the pose at this frame.", paste))
	bar.add_child(_btn("Delete keys", "keydel", "Delete", "Deletes the selected keys (none selected: the bone's key at this frame).", delete_keys))
	box.add_child(bar)
	_sheet = Sheet.new()
	_sheet.ed = self
	_sheet.size_flags_vertical = SIZE_EXPAND_FILL
	_sheet.custom_minimum_size.y = 150
	_sheet.clip_contents = true
	_sheet.tooltip_text = EditorIcons.tip("Dope sheet", "", "Each bone's keys along time. The ruler: scrub. Click a key to select it (Shift: add),\ndrag to move them; a bone's name selects it; the wheel scrolls the bones.")
	box.add_child(_sheet)
	return box


func _btn(name: String, icon: String, keys: String, help: String, cb: Callable) -> Button:
	var b := UI.button("", cb, 14)
	b.focus_mode = FOCUS_NONE
	return EditorIcons.dress(b, icon, EditorIcons.tip(name, keys, help))


# --- Characters ------------------------------------------------------------------

## Shows character `id` (its model loaded on a worker the first time, not headless).
func open_character(id: String) -> void:
	if id == "" or not Stage3D.has_model(id):
		return
	if _chars:
		for i in _chars.item_count:
			if _chars.get_item_text(i) == id:
				_chars.select(i)
	if not Stage3D._scenes.has(id) and DisplayServer.get_name() != "headless":
		var path := Stage3D.model_dir(id) + id + ".glb"
		if ResourceLoader.load_threaded_request(path) == OK:
			_loading = id
			_say("loading %s..." % id)
			return
	_show_model(id)


func _show_model(id: String) -> void:
	_loading = ""
	char_id = id
	if _model:
		_model.queue_free()
	var model: Node3D = Stage3D._scene(id).instantiate()
	var mats: Dictionary = Stage3D.info(id).get("materials", {})
	var hide: Array = HIDE_MIN if mats.keys().any(func(m): return str(m).begins_with("MIN_")) else []
	CosmosModels.apply(model, id, [], hide)   # (as the game draws it: merged, physically based)
	_vp.add_child(model)
	_model = model
	_sk = model.find_child("Skeleton3D", true, false)
	_ap = model.find_child("AnimationPlayer", true, false)
	var mi: MeshInstance3D = model.find_child("Body", true, false)
	if mi:
		mi.extra_cull_margin = 4.0
	_fps = float(Stage3D.info(id)["fps"])
	if not _docs.has(id):
		Stage3D.forget_clips(id)   # (the clip files listed afresh: the target may have changed)
	if _ap:
		Stage3D.loop_clips(_ap, id)    # (the clips as the game has them: lengths, loops, glitches mended, files used)
		_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_ap.active = false             # (the editor poses the skeleton itself)
		_prefix = str(_ap.get_node(_ap.root_node).get_path_to(_sk)) if _sk else _prefix
	_children = []
	for b in _sk.get_bone_count():
		_children.append([])
	for b in _sk.get_bone_count():
		var p := _sk.get_bone_parent(b)
		if p >= 0:
			_children[p].append(b)
	if not _docs.has(id):
		_docs[id] = _new_doc(id)
	bone = -1
	sel_keys.clear()
	pose.clear()
	var doc := _doc()
	select_clip(clip if doc["clips"].has(clip) else ("idle" if doc["clips"].has("idle") else (str(doc["order"][0]) if not doc["order"].is_empty() else "")))
	_say("")


func _new_doc(id: String) -> Dictionary:
	var doc := {"clips": {}, "order": [], "base": {}, "files": {}, "changed": {}, "removed": {}, "undo": [], "redo": []}
	var names: Array = Stage3D.info(id).get("clips", {}).keys()
	if _ap:
		for n in _ap.get_animation_list():
			if not names.has(str(n)):
				names.append(str(n))
	var files := Stage3D.custom_clips(id)
	for n in names:
		var a := Stage3D.base_clip(_ap, id, n)
		if a != null:
			doc["base"][n] = true
			doc["clips"][n] = files.get(n, a)
			doc["order"].append(n)
	for n in files:
		doc["files"][n] = true
		if not doc["clips"].has(n):
			doc["clips"][n] = files[n]
			doc["order"].append(n)
	return doc


func _doc() -> Dictionary:
	return _docs.get(char_id, {})


## The clip showing (null: none).
func anim() -> Animation:
	var d := _doc()
	return d.get("clips", {}).get(clip)


# --- Clips -----------------------------------------------------------------------

func select_clip(name: String) -> void:
	var d := _doc()
	if d.is_empty() or not d["clips"].has(name):
		clip = ""
	else:
		clip = name
	playing = false
	sel_keys.clear()
	pose.clear()
	time = 0.0
	frame = 0
	_fill_clips()
	_refresh_keys()
	_sync_clip_fields()
	_apply()


## Frames in the clip (a loop: its length; else its last frame included).
func frames() -> int:
	var a := anim()
	if a == null:
		return 0
	return maxi(1, roundi(a.length * _fps) + (0 if a.loop_mode != Animation.LOOP_NONE else 1))


func _fill_clips() -> void:
	if _clip_list == null:
		return
	_clip_list.clear()
	var d := _doc()
	if d.is_empty():
		return
	for n in d["order"]:
		var a: Animation = d["clips"][n]
		var nf := maxi(1, roundi(a.length * _fps) + (0 if a.loop_mode != Animation.LOOP_NONE else 1))
		var mark := " [own]" if not d["base"].has(n) else (" [file]" if d["files"].has(n) and not d["removed"].has(n) else "")
		var i := _clip_list.add_item("%s%s   %d f%s%s" % ["* " if d["changed"].has(n) else "", n, nf, "  loop" if a.loop_mode != Animation.LOOP_NONE else "", mark])
		_clip_list.set_item_metadata(i, n)
		if n == clip:
			_clip_list.select(i)
			_clip_list.ensure_current_is_visible()


func _sync_clip_fields() -> void:
	if _name_edit == null:
		return
	_syncing = true
	var d := _doc()
	var own: bool = clip != "" and not d["base"].has(clip)
	_name_edit.text = clip
	_name_edit.editable = own
	_len_spin.value = frames()
	_loop_check.button_pressed = anim() != null and anim().loop_mode != Animation.LOOP_NONE
	_del_btn.disabled = clip == "" or not (own or (d["files"].has(clip) and not d["removed"].has(clip)) or d["changed"].has(clip))
	_syncing = false
	_frame_label.text = "%d / %d" % [frame, maxi(0, frames() - 1)]


## A new clip of your own: empty (the rest pose), or a copy of the selected one.
func new_clip(copy: bool) -> void:
	var d := _doc()
	if d.is_empty():
		return
	var base := (clip + "_copy") if copy and clip != "" else "clip"
	var name := base
	var n := 2
	while d["clips"].has(name):
		name = "%s_%d" % [base, n]
		n += 1
	_edit()
	var a: Animation
	if copy and anim() != null:
		a = anim().duplicate(true)
	else:
		a = Animation.new()
		a.length = 29.0 / _fps
		a.step = 1.0 / _fps
	d["clips"][name] = a
	d["order"].append(name)
	d["changed"][name] = true
	_fresh = a
	select_clip(name)
	_after_edit()


## Renames your own clip.
func rename_clip(to: String) -> void:
	var d := _doc()
	to = to.strip_edges().replace(" ", "_").validate_filename()
	if clip == "" or d["base"].has(clip) or to == "" or to == clip:
		_sync_clip_fields()
		return
	if d["clips"].has(to):
		_say("there's a clip called %s already" % to)
		_sync_clip_fields()
		return
	_edit()
	var old := clip
	d["clips"][to] = d["clips"][old]
	d["clips"].erase(old)
	d["order"][d["order"].find(old)] = to
	d["changed"].erase(old)
	d["changed"][to] = true
	if d["files"].has(old):
		d["removed"][old] = true
	clip = to
	_after_edit()


## Deletes your own clip; the model's clip goes back to the model's own (its file deleted on Save).
func delete_clip() -> void:
	var d := _doc()
	if clip == "":
		return
	_edit()
	var name := clip
	d["changed"].erase(name)
	if d["files"].has(name):
		d["removed"][name] = true
	if d["base"].has(name):
		d["clips"][name] = Stage3D.base_clip(_ap, char_id, name)
		_after_edit()
		select_clip(name)
		return
	d["clips"].erase(name)
	d["order"].erase(name)
	select_clip(str(d["order"][0]) if not d["order"].is_empty() else "")
	_after_edit()


func set_length(n: int) -> void:
	var a := anim()
	if a == null or n == frames():
		return
	_edit()
	a = _writable()
	a.length = (n if a.loop_mode != Animation.LOOP_NONE else n - 1) / _fps
	_after_edit()


func set_loop(on: bool) -> void:
	var a := anim()
	if a == null or (a.loop_mode != Animation.LOOP_NONE) == on:
		return
	var n := frames()
	_edit()
	a = _writable()
	a.loop_mode = Animation.LOOP_LINEAR if on else Animation.LOOP_NONE
	a.length = (n if on else n - 1) / _fps
	_after_edit()


# --- Edits and undo --------------------------------------------------------------

## Starts an edit of the clip showing: an undo step (the document as it is), marked changed.
func _edit() -> void:
	var d := _doc()
	d["undo"].append(_snap(d))
	if d["undo"].size() > UNDO_MAX:
		d["undo"].pop_front()
	d["redo"].clear()
	_fresh = null
	if clip != "":
		d["changed"][clip] = true


## The clip showing, ready to change (a copy the first time in an edit: what undo holds stays as it was).
func _writable() -> Animation:
	var d := _doc()
	var a: Animation = d["clips"][clip]
	if a != _fresh:
		a = a.duplicate(true)
		d["clips"][clip] = a
		_fresh = a
	return a


func _after_edit() -> void:
	_update_dirty()
	_fill_clips()
	_refresh_keys()
	_sync_clip_fields()
	_apply()


func _snap(d: Dictionary) -> Dictionary:
	return {"clips": d["clips"].duplicate(), "order": d["order"].duplicate(), "changed": d["changed"].duplicate(),
		"removed": d["removed"].duplicate(), "clip": clip, "frame": frame}


func _restore(d: Dictionary, s: Dictionary) -> void:
	for k in ["clips", "order", "changed", "removed"]:
		d[k] = s[k].duplicate()
	_fresh = null
	var f: int = s["frame"]
	select_clip(str(s["clip"]) if d["clips"].has(s["clip"]) else (str(d["order"][0]) if not d["order"].is_empty() else ""))
	set_frame(f)
	_update_dirty()


func undo() -> void:
	var d := _doc()
	if d.is_empty() or d["undo"].is_empty():
		return
	d["redo"].append(_snap(d))
	_restore(d, d["undo"].pop_back())
	_say("undone")


func redo() -> void:
	var d := _doc()
	if d.is_empty() or d["redo"].is_empty():
		return
	d["undo"].append(_snap(d))
	_restore(d, d["redo"].pop_back())
	_say("redone")


func _update_dirty() -> void:
	dirty = false
	for id in _docs:
		var d: Dictionary = _docs[id]
		if not d["changed"].is_empty() or not d["removed"].is_empty():
			dirty = true
	_refresh_header()


func _refresh_header() -> void:
	if _save_btn == null:
		return
	_save_btn.disabled = not EditTarget.writable()
	var d := _doc()
	_undo_btn.disabled = d.is_empty() or d["undo"].is_empty()
	_redo_btn.disabled = d.is_empty() or d["redo"].is_empty()


func _say(msg: String) -> void:
	if _note:
		_note.text = (msg + "  -  " if msg != "" else "") + "saving into " + EditTarget.label() + ("  (unsaved changes)" if dirty else "")


# --- Saving ----------------------------------------------------------------------

## Writes every changed clip (art/<id>_3d/clips/<clip>.tres, through EditTarget) and
## deletes the files of clips deleted; the game's models use them from now on.
func save() -> bool:
	if not EditTarget.writable():
		_say("can't save here: make a mod (the Mod Editor)")
		return false
	var wrote := 0
	var failed := 0
	for id in _docs:
		var d: Dictionary = _docs[id]
		if d["changed"].is_empty() and d["removed"].is_empty():
			continue
		var dir := Stage3D.clips_dir(id)
		for name in d["removed"]:
			if d["changed"].has(name):
				continue
			var p := EditTarget.write_path(dir + name + ".tres")
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)
			d["files"].erase(name)
		for name in d["changed"]:
			var a: Animation = d["clips"][name]
			var p := EditTarget.write_path(dir + name + ".tres")
			DirAccess.make_dir_recursive_absolute(p.get_base_dir())   # (the game's own clips/ folder, the first time)
			var out: Animation = a.duplicate(true)   # (a clean resource: no path, the model's or another file's)
			out.resource_name = name
			if ResourceSaver.save(out, p) == OK:
				d["files"][name] = true
				wrote += 1
			else:
				failed += 1
		d["changed"].clear()
		d["removed"].clear()
		Stage3D.forget_clips(id)   # (the game's models take the files from now on)
		if id == char_id and _ap:
			Stage3D.use_clips(_ap, id)
	_update_dirty()
	_fill_clips()
	_sync_clip_fields()
	_say(("saved %d clip%s" % [wrote, "" if wrote == 1 else "s"]) + (" (%d failed)" % failed if failed > 0 else ""))
	return failed == 0


## Drops every unsaved edit (the clips as saved).
func discard() -> void:
	_docs.clear()
	dirty = false
	_fresh = null
	if char_id != "":
		Stage3D.forget_clips(char_id)
		_show_model(char_id)
	_refresh_header()


## Asks about unsaved changes (save / discard / stay), then `next`.
func guard(next: Callable) -> void:
	if not dirty:
		next.call()
		return
	UI.unsaved(self, "The animation editor", func(): save(), discard, next)


## The Mod Editor switched mods: save into the new one (re-read when nothing's unsaved).
func target_changed() -> void:
	if not dirty and char_id != "":
		_docs.clear()
		Stage3D.forget_clips(char_id)
		_show_model(char_id)
	_refresh_header()
	_say("")


func talos_shown() -> void:
	_redraw()
	_refresh_header()


# --- Keys ------------------------------------------------------------------------

func _bone_name(b: int) -> String:
	return _sk.get_bone_name(b) if _sk and b >= 0 and b < _sk.get_bone_count() else ""


## The track of `type` for bone `b` in `a` (-1: none).
func _track(a: Animation, b: int, type: int) -> int:
	return a.find_track(NodePath(_prefix + ":" + _bone_name(b)), type)


## The bone's tracks in `a` (position, rotation, scale).
func _bone_tracks(a: Animation, b: int) -> Array:
	var out: Array = []
	for type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
		var t := _track(a, b, type)
		if t >= 0:
			out.append(t)
	return out


func _key_at(a: Animation, t: int, f: int) -> int:
	for k in a.track_get_key_count(t):
		if roundi(a.track_get_key_time(t, k) * _fps) == f:
			return k
	return -1


func _add_track(a: Animation, b: int, type: int) -> int:
	var t := a.add_track(type)
	a.track_set_path(t, NodePath(_prefix + ":" + _bone_name(b)))
	a.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
	return t


## Sets bone `b`'s key of `type` at frame `f` (a track made when it has none).
func _set_key(a: Animation, b: int, type: int, f: int, value: Variant) -> void:
	var t := _track(a, b, type)
	if t < 0:
		t = _add_track(a, b, type)
	var k := _key_at(a, t, f)
	if k >= 0:
		a.track_set_key_value(t, k, value)
	else:
		a.track_insert_key(t, f / _fps, value)


## Bone `b`'s key value of `type` at frame `f` in the clip showing (null: no key there).
func key_value(b: Variant, f: int, type := Animation.TYPE_ROTATION_3D) -> Variant:
	var a := anim()
	var i: int = _sk.find_bone(b) if b is String else int(b)
	if a == null or i < 0:
		return null
	var t := _track(a, i, type)
	if t < 0:
		return null
	var k := _key_at(a, t, f)
	return a.track_get_key_value(t, k) if k >= 0 else null


## The bone's pose shown now: {rot, pos}.
func bone_pose(b: int) -> Dictionary:
	return {"rot": _sk.get_bone_pose_rotation(b), "pos": _sk.get_bone_pose_position(b)}


func _keys_bone(a: Animation, b: int) -> void:
	var p := bone_pose(b)
	_set_key(a, b, Animation.TYPE_ROTATION_3D, frame, p["rot"])
	if _track(a, b, Animation.TYPE_POSITION_3D) >= 0 or (pose.has(b) and pose[b].has("pos")):
		_set_key(a, b, Animation.TYPE_POSITION_3D, frame, p["pos"])


## Keys the selected bone (or `b`) at this frame - its pose as shown.
func key_bone(b := -2) -> void:
	if b == -2:
		b = bone
	if anim() == null or b < 0:
		_say("select a bone first" if anim() != null else "no clip")
		return
	_edit()
	_keys_bone(_writable(), b)
	pose.erase(b)
	_after_edit()
	_say("keyed %s at %d" % [_bone_name(b), frame])


## Keys every bone at this frame.
func key_all() -> void:
	if anim() == null:
		return
	_edit()
	var a := _writable()
	for b in _sk.get_bone_count():
		_keys_bone(a, b)
	pose.clear()
	_after_edit()
	_say("keyed every bone at %d" % frame)


## Gives bone `b` a pose (not keyed till K - or at once with Auto-key).
func pose_bone(b: int, rot: Variant = null, pos: Variant = null) -> void:
	if b < 0:
		return
	var p: Dictionary = pose.get(b, {})
	if rot != null:
		p["rot"] = (rot as Quaternion).normalized()
	if pos != null:
		p["pos"] = pos
	pose[b] = p
	_apply()
	if auto_key and anim() != null:
		key_bone(b)


func clear_pose() -> void:
	pose.clear()
	_apply()


func rest_bone() -> void:
	if bone >= 0:
		var r := _sk.get_bone_rest(bone)
		pose_bone(bone, r.basis.get_rotation_quaternion(), r.origin)


func set_interpolation(i: int) -> void:
	var a := anim()
	if a == null or bone < 0 or _bone_tracks(a, bone).is_empty():
		return
	_edit()
	a = _writable()
	for t in _bone_tracks(a, bone):
		a.track_set_interpolation_type(t, [Animation.INTERPOLATION_LINEAR, Animation.INTERPOLATION_CUBIC, Animation.INTERPOLATION_NEAREST][i])
	_after_edit()


## The selected keys (or the bone's key at this frame): every track of the bone there.
func _picked() -> Array:
	if not sel_keys.is_empty():
		return sel_keys.keys()
	return [Vector2i(bone, frame)] if bone >= 0 else []


func delete_keys() -> void:
	var a := anim()
	var picked := _picked()
	if a == null or picked.is_empty():
		return
	_edit()
	a = _writable()
	for v in picked:
		for t in _bone_tracks(a, v.x):
			var k := _key_at(a, t, v.y)
			if k >= 0:
				a.track_remove_key(t, k)
	sel_keys.clear()
	_after_edit()


## Moves the selected keys `by` frames (keys where they land replaced).
func move_keys(by: int) -> void:
	var a := anim()
	if a == null or by == 0 or sel_keys.is_empty():
		return
	_edit()
	a = _writable()
	var moving: Array = []                # [track, to frame, value]
	for v in sel_keys:
		for t in _bone_tracks(a, v.x):
			var k := _key_at(a, t, v.y)
			if k >= 0:
				moving.append([t, maxi(0, v.y + by), a.track_get_key_value(t, k)])
				a.track_remove_key(t, k)
	for m in moving:
		var k := _key_at(a, m[0], m[1])
		if k >= 0:
			a.track_remove_key(m[0], k)
		a.track_insert_key(m[0], m[1] / _fps, m[2])
	var moved := {}
	for v in sel_keys:
		moved[Vector2i(v.x, maxi(0, v.y + by))] = true
	sel_keys = moved
	_after_edit()


func copy() -> void:
	var a := anim()
	if a == null:
		return
	if sel_keys.is_empty():
		copy_pose()
		return
	var lo := 1 << 30
	for v in sel_keys:
		lo = mini(lo, v.y)
	var items: Array = []
	for v in sel_keys:
		for t in _bone_tracks(a, v.x):
			var k := _key_at(a, t, v.y)
			if k >= 0:
				items.append({"bone": _bone_name(v.x), "type": a.track_get_type(t), "df": v.y - lo, "value": a.track_get_key_value(t, k)})
	clipboard = {"kind": "keys", "items": items}
	_say("copied %d keys" % sel_keys.size())


func copy_pose() -> void:
	if _sk == null:
		return
	var bones := {}
	var a := anim()
	for b in _sk.get_bone_count():
		var p := bone_pose(b)
		var e := {"rot": p["rot"]}
		if a != null and _track(a, b, Animation.TYPE_POSITION_3D) >= 0:
			e["pos"] = p["pos"]
		bones[_bone_name(b)] = e
	clipboard = {"kind": "pose", "bones": bones}
	_say("copied the pose at %d" % frame)


func paste() -> void:
	if anim() == null or clipboard.is_empty():
		return
	_edit()
	var a := _writable()
	if clipboard["kind"] == "keys":
		for it in clipboard["items"]:
			var b := _sk.find_bone(it["bone"])
			if b >= 0:
				_set_key(a, b, it["type"], frame + int(it["df"]), it["value"])
	else:
		for n in clipboard["bones"]:
			var b := _sk.find_bone(n)
			if b < 0:
				continue
			var e: Dictionary = clipboard["bones"][n]
			_set_key(a, b, Animation.TYPE_ROTATION_3D, frame, e["rot"])
			if e.has("pos"):
				_set_key(a, b, Animation.TYPE_POSITION_3D, frame, e["pos"])
	pose.clear()
	_after_edit()
	_say("pasted at %d" % frame)


## Each bone's key frames, for the dope sheet.
func _refresh_keys() -> void:
	_rows = []
	var a := anim()
	if _sk == null:
		return
	for b in _sk.get_bone_count():
		var fs := {}
		if a != null:
			for t in _bone_tracks(a, b):
				for k in a.track_get_key_count(t):
					fs[roundi(a.track_get_key_time(t, k) * _fps)] = true
		var arr := PackedInt32Array(fs.keys())
		arr.sort()
		_rows.append(arr)
	if _sheet:
		_sheet.queue_redraw()


func rows() -> Array:
	return _rows


# --- Time ------------------------------------------------------------------------

func set_frame(f: int) -> void:
	var n := frames()
	f = clampi(f, 0, maxi(0, n - 1))
	frame = f
	time = f / _fps
	pose.clear()
	_apply()


func step(by: int) -> void:
	playing = false
	var n := frames()
	if n <= 0:
		return
	set_frame(posmod(frame + by, n) if loop_play else frame + by)


func jump_key(dir: int) -> void:
	var fs := {}
	for b in _rows.size():
		if bone >= 0 and b != bone:
			continue
		for f in _rows[b]:
			fs[f] = true
	var best := -1
	for f in fs:
		if (dir > 0 and f > frame and (best < 0 or f < best)) or (dir < 0 and f < frame and (best < 0 or f > best)):
			best = f
	if best >= 0:
		playing = false
		set_frame(best)


func toggle_play() -> void:
	if anim() == null:
		return
	playing = not playing
	pose.clear()
	if playing and frame >= frames() - 1 and not loop_play:
		time = 0.0
	_play_btn.icon = EditorIcons.get_icon("stop" if playing else "play")
	_apply()


func _process(delta: float) -> void:
	if _loading != "":
		var path := Stage3D.model_dir(_loading) + _loading + ".glb"
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			Stage3D._scenes[_loading] = ResourceLoader.load_threaded_get(path)
			_show_model(_loading)
		elif st != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			_show_model(_loading)   # (failed on the worker: loaded here)
		return
	if not playing:
		return
	var a := anim()
	if a == null:
		playing = false
		return
	time += delta * speed
	var end := a.length
	if time >= end:
		if loop_play and end > 0.0:
			time = fmod(time, end)
		else:
			time = end
			playing = false
			_play_btn.icon = EditorIcons.get_icon("play")
	frame = clampi(int(time * _fps + 0.0001), 0, maxi(0, frames() - 1))
	_apply()


# --- The pose and the view -------------------------------------------------------

## Poses the skeleton as the clip has it at `t` (Godot's own interpolation).
func _sample(a: Animation, t: float) -> void:
	_sk.reset_bone_poses()
	if a == null:
		return
	for tr in a.get_track_count():
		if a.track_get_key_count(tr) == 0 or not a.track_is_enabled(tr):
			continue
		var b := _sk.find_bone(String(a.track_get_path(tr).get_concatenated_subnames()))
		if b < 0:
			continue
		match a.track_get_type(tr):
			Animation.TYPE_POSITION_3D:
				_sk.set_bone_pose_position(b, a.position_track_interpolate(tr, t))
			Animation.TYPE_ROTATION_3D:
				_sk.set_bone_pose_rotation(b, a.rotation_track_interpolate(tr, t))
			Animation.TYPE_SCALE_3D:
				_sk.set_bone_pose_scale(b, a.scale_track_interpolate(tr, t))


## The pose shown now: the clip at this time, plus the pose not keyed yet.
func _apply() -> void:
	if _sk == null:
		return
	_sample(anim(), time)
	for b in pose:
		if pose[b].has("rot"):
			_sk.set_bone_pose_rotation(b, pose[b]["rot"])
		if pose[b].has("pos"):
			_sk.set_bone_pose_position(b, pose[b]["pos"])
	_sync_bone_fields()
	if _frame_label:
		_frame_label.text = "%d / %d" % [frame, maxi(0, frames() - 1)]
	_redraw()


func _redraw() -> void:
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if _view:
		_view.queue_redraw()
	if _sheet:
		_sheet.head.queue_redraw()
	_refresh_header()


## Every bone's place on screen now (Vector2 per bone).
func screen_bones() -> Array:
	var out: Array = []
	if _sk == null or _cam == null:
		return out
	var g := _sk.global_transform
	for b in _sk.get_bone_count():
		var p := g * _sk.get_bone_global_pose(b).origin
		out.append(_cam.unproject_position(p) if not _cam.is_position_behind(p) else Vector2(-9999, -9999))
	return out


## Bone `b` drawn from its place to its first child's (a leaf: a short stub along it).
func bone_tail(b: int, pts: Array) -> Vector2:
	if not _children[b].is_empty():
		return pts[_children[b][0]]
	var g := _sk.global_transform * _sk.get_bone_global_pose(b)
	var tip := g * Vector3(0, 0.08, 0)
	return _cam.unproject_position(tip)


## The ghosts' bones on screen: [[frame offset, points]...] (the onion skin).
func onion_bones() -> Array:
	var out: Array = []
	var a := anim()
	if not onion or a == null:
		return out
	var n := frames()
	for off in ONION:
		var f: int = frame + off
		if a.loop_mode != Animation.LOOP_NONE:
			f = posmod(f, n)
		elif f < 0 or f >= n:
			continue
		_sample(a, f / _fps)
		out.append([off, screen_bones()])
	_apply_quiet()
	return out


## The pose put back without a redraw (after the onion skin's sampling).
func _apply_quiet() -> void:
	_sample(anim(), time)
	for b in pose:
		if pose[b].has("rot"):
			_sk.set_bone_pose_rotation(b, pose[b]["rot"])
		if pose[b].has("pos"):
			_sk.set_bone_pose_position(b, pose[b]["pos"])


## The bone nearest `at` on screen (within 14 px), or -1.
func pick(at: Vector2) -> int:
	var pts := screen_bones()
	var best := -1
	var best_d := 14.0
	for b in pts.size():
		var a: Vector2 = pts[b]
		var d := Geometry2D.get_closest_point_to_segment(at, a, bone_tail(b, pts)).distance_to(at)
		d = minf(d, a.distance_to(at) - 2.0)
		if d < best_d:
			best_d = d
			best = b
	return best


func select_bone(b: Variant) -> void:
	bone = _sk.find_bone(b) if b is String else int(b)
	_sync_bone_fields()
	_redraw()
	if _sheet:
		_sheet.show_bone(bone)
		_sheet.queue_redraw()


func _sync_bone_fields() -> void:
	if _bone_label == null:
		return
	_syncing = true
	var on := bone >= 0 and _sk != null
	_bone_label.text = (_bone_name(bone) + ("  (not keyed)" if pose.has(bone) else "")) if on else "(click a bone)"
	if on:
		var p := bone_pose(bone)
		var e: Vector3 = (p["rot"] as Quaternion).get_euler()
		for i in 3:
			_rot[i].value = rad_to_deg(e[i])
			_pos[i].value = p["pos"][i]
		var a := anim()
		var ts := _bone_tracks(a, bone) if a else []
		if not ts.is_empty():
			var it := a.track_get_interpolation_type(ts[0])
			_interp.select(2 if it == Animation.INTERPOLATION_NEAREST else (1 if it in [Animation.INTERPOLATION_CUBIC, Animation.INTERPOLATION_CUBIC_ANGLE] else 0))
	for s in _rot + _pos:
		s.editable = on
	_interp.disabled = not on
	_syncing = false


func _fields_changed(which: String) -> void:
	if bone < 0:
		return
	if which == "rot":
		var e := Vector3(deg_to_rad(_rot[0].value), deg_to_rad(_rot[1].value), deg_to_rad(_rot[2].value))
		pose_bone(bone, Quaternion.from_euler(e))
	else:
		pose_bone(bone, null, Vector3(_pos[0].value, _pos[1].value, _pos[2].value))


## The camera: orbiting `target` at `dist`, `yaw` round, `pitch` up.
func _aim() -> void:
	if _cam == null:
		return
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	_cam.look_at_from_position(target + dir * dist, target, Vector3.UP)
	_redraw()


## Front / side / top.
func view(which: String) -> void:
	match which:
		"front":
			yaw = 0.0
			pitch = 0.0
		"side":
			yaw = -PI * 0.5
			pitch = 0.0
		"top":
			yaw = 0.0
			pitch = deg_to_rad(89.0)
	_aim()


## The bone's parent's turn in the world (identity-free: the skeleton's own too).
func _parent_xf(b: int) -> Transform3D:
	var g := _sk.global_transform
	var p := _sk.get_bone_parent(b)
	return g * _sk.get_bone_global_pose(p) if p >= 0 else g


## R / G: starts turning or moving the selected bone with the mouse.
func start_modal(kind: String) -> void:
	if bone < 0 or _sk == null:
		return
	var p := bone_pose(bone)
	_modal = {"kind": kind, "axis": -1, "start": _view.get_local_mouse_position(), "rot": p["rot"], "pos": p["pos"], "had": pose.get(bone, {}).duplicate()}


func _modal_update(at: Vector2) -> void:
	var d: Vector2 = at - _modal["start"]
	var ax: int = _modal["axis"]
	if _modal["kind"] == "rot":
		var ang := d.x * deg_to_rad(0.5)
		var q0: Quaternion = _modal["rot"]
		var q: Quaternion
		if ax >= 0:
			q = q0 * Quaternion([Vector3.RIGHT, Vector3.UP, Vector3.BACK][ax], ang)
		else:
			var pb := _parent_xf(bone).basis.orthonormalized()
			var w := -_cam.global_transform.basis.z
			q = Quaternion(pb.transposed() * Basis(w, ang) * pb) * q0
		pose[bone] = {"rot": q.normalized(), "pos": _sk.get_bone_pose_position(bone)} if pose.get(bone, {}).has("pos") else {"rot": q.normalized()}
		_say("turning %s%s: %.1f deg" % [_bone_name(bone), (" round " + "XYZ"[ax]) if ax >= 0 else "", rad_to_deg(ang)])
	else:
		var s := dist * 0.0015
		var pb := _parent_xf(bone).basis
		var delta: Vector3
		if ax >= 0:
			delta = [Vector3.RIGHT, Vector3.UP, Vector3.BACK][ax] * d.x * s
		else:
			var cb := _cam.global_transform.basis
			delta = pb.inverse() * (cb.x * d.x * s - cb.y * d.y * s)
		var e: Dictionary = pose.get(bone, {}).duplicate()
		e["pos"] = (_modal["pos"] as Vector3) + delta
		pose[bone] = e
		_say("moving %s%s" % [_bone_name(bone), (" along " + "XYZ"[ax]) if ax >= 0 else ""])
	_apply()


func end_modal(keep: bool) -> void:
	if _modal.is_empty():
		return
	if not keep:
		if (_modal["had"] as Dictionary).is_empty():
			pose.erase(bone)
		else:
			pose[bone] = _modal["had"]
		_modal = {}
		_apply()
		_say("")
		return
	_modal = {}
	if auto_key and anim() != null:
		key_bone(bone)
	else:
		_apply()
		_say("%s posed - K keys it" % _bone_name(bone))


func view_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed:
		if not _modal.is_empty():
			end_modal(mb.button_index == MOUSE_BUTTON_LEFT)
			return
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.alt_pressed:
					_drag = "orbit"
				else:
					var b := pick(mb.position)
					if b >= 0 or not mb.shift_pressed:
						select_bone(b)
			MOUSE_BUTTON_RIGHT:
				_drag = "pan" if mb.shift_pressed else "orbit"
			MOUSE_BUTTON_MIDDLE:
				_drag = "pan"
			MOUSE_BUTTON_WHEEL_UP:
				dist = maxf(0.4, dist * 0.9)
				_aim()
			MOUSE_BUTTON_WHEEL_DOWN:
				dist = minf(30.0, dist * 1.1)
				_aim()
	elif mb and not mb.pressed:
		_drag = ""
	var mm := event as InputEventMouseMotion
	if mm:
		if not _modal.is_empty():
			_modal_update(mm.position)
		elif _drag == "orbit":
			yaw -= mm.relative.x * 0.01
			pitch = clampf(pitch + mm.relative.y * 0.01, deg_to_rad(-89.0), deg_to_rad(89.0))
			_aim()
		elif _drag == "pan":
			var cb := _cam.global_transform.basis
			target += (-cb.x * mm.relative.x + cb.y * mm.relative.y) * dist * 0.0015
			_aim()


# --- Keys ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or has_meta("talos_parked"):
		return
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	if k.echo and k.keycode not in [KEY_LEFT, KEY_RIGHT]:
		return
	var handled := true
	if not _modal.is_empty():
		match k.keycode:
			KEY_X, KEY_Y, KEY_Z:
				_modal["axis"] = {KEY_X: 0, KEY_Y: 1, KEY_Z: 2}[k.keycode]
				_modal_update(_view.get_local_mouse_position())
			KEY_ENTER, KEY_KP_ENTER:
				end_modal(true)
			KEY_ESCAPE:
				end_modal(false)
			_:
				handled = false
	elif k.ctrl_pressed:
		match k.keycode:
			KEY_S:
				save()
			KEY_Z:
				if k.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_C:
				if k.shift_pressed:
					copy_pose()
				else:
					copy()
			KEY_V:
				paste()
			KEY_LEFT:
				jump_key(-1)
			KEY_RIGHT:
				jump_key(1)
			_:
				handled = false
	else:
		match k.keycode:
			KEY_SPACE:
				toggle_play()
			KEY_LEFT:
				step(-1)
			KEY_RIGHT:
				step(1)
			KEY_HOME:
				set_frame(0)
			KEY_END:
				set_frame(frames() - 1)
			KEY_K:
				if k.shift_pressed:
					key_all()
				else:
					key_bone()
			KEY_R:
				if k.alt_pressed:
					clear_pose()
				else:
					start_modal("rot")
			KEY_G:
				start_modal("pos")
			KEY_DELETE, KEY_BACKSPACE:
				delete_keys()
			KEY_L:
				_loop_play_check.button_pressed = not loop_play
			KEY_O:
				_onion_check.button_pressed = not onion
			KEY_KP_1:
				view("front")
			KEY_KP_3:
				view("side")
			KEY_KP_7:
				view("top")
			KEY_F1:
				EditorDocs.open(self, "anim")
			KEY_ESCAPE:
				if not sel_keys.is_empty() or bone >= 0:
					sel_keys.clear()
					select_bone(-1)
				elif not embedded:
					get_viewport().set_input_as_handled()   # (before: leaving may free the scene)
					TalosNav.go(get_tree(), "menu", guard)
					return
				else:
					handled = false
			_:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


# --- The view's overlay: the skeleton, picking, the camera -----------------------

class Overlay extends Control:
	var ed

	func _gui_input(event: InputEvent) -> void:
		ed.view_input(event)
		if event is InputEventMouseButton or event is InputEventMouseMotion:
			accept_event()

	func _draw() -> void:
		if ed._sk == null:
			return
		for g in ed.onion_bones():
			var c := Color(0.45, 0.7, 1.0, 0.35) if g[0] < 0 else Color(1.0, 0.7, 0.3, 0.35)
			_bones(g[1], c, c, 1.5)
		_bones(ed.screen_bones(), Color(0.9, 0.95, 1.0, 0.75), NeonTheme.PINK, 2.0)
		if ed.char_id != "" and ed.anim() == null:
			draw_string(get_theme_default_font(), Vector2(12, 24), "no clip", HORIZONTAL_ALIGNMENT_LEFT, -1, ed.FS, UI.TEXT_DIM)

	func _bones(pts: Array, c: Color, sel: Color, w: float) -> void:
		for b in pts.size():
			var a: Vector2 = pts[b]
			if a.x < -9000:
				continue
			var on: bool = b == ed.bone
			var col: Color = sel if on else c
			var t: Vector2 = ed.bone_tail(b, pts)
			draw_line(a, t, Color(0, 0, 0, col.a * 0.6), w + 2.0, true)
			draw_line(a, t, col, w + (1.5 if on else 0.0), true)
			draw_circle(a, 3.5 if on else 2.5, col)


# --- The dope sheet: bones down the side, keys along time ------------------------

class Sheet extends Control:
	var ed
	var head: Control
	var top_row := 0
	var _press := ""                   # "scrub" / "keys"
	var _from := Vector2.ZERO
	var _by := 0

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		focus_mode = FOCUS_CLICK   # (a click here takes the keys back from a typed field)
		head = Head.new()
		head.sheet = self
		head.mouse_filter = MOUSE_FILTER_IGNORE
		head.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		add_child(head)

	func px() -> float:
		return (size.x - ed.NAME_W - 16.0) / float(maxi(1, ed.frames() - 1))

	func fx(f: float) -> float:
		return ed.NAME_W + 8.0 + f * px()

	func frame_at(x: float) -> int:
		return clampi(roundi((x - ed.NAME_W - 8.0) / px()), 0, maxi(0, ed.frames() - 1))

	func visible_rows() -> int:
		return maxi(1, int((size.y - ed.RULER_H) / ed.ROW_H))

	func row_at(y: float) -> int:
		var r := top_row + int((y - ed.RULER_H) / ed.ROW_H)
		return r if y >= ed.RULER_H and r < ed.rows().size() else -1

	func show_bone(b: int) -> void:
		if b < 0:
			return
		if b < top_row:
			top_row = b
		elif b >= top_row + visible_rows():
			top_row = b - visible_rows() + 1

	func _draw() -> void:
		var font := get_theme_default_font()
		var fs: int = ed.FS
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.025, 0.02, 0.9))
		var n: int = ed.frames()
		# The ruler.
		draw_rect(Rect2(0, 0, size.x, ed.RULER_H), Color(0.08, 0.055, 0.03))
		var every := 1
		while every * px() < 34.0:
			every = [1, 2, 5, 10, 15, 30, 60, 90, 150, 300][mini(9, [1, 2, 5, 10, 15, 30, 60, 90, 150, 300].find(every) + 1)]
			if every >= 300:
				break
		for f in range(0, n, every):
			var x := fx(f)
			draw_line(Vector2(x, ed.RULER_H - 6), Vector2(x, ed.RULER_H), UI.TEXT_DIM)
			draw_string(font, Vector2(x + 2, ed.RULER_H - 7), str(f), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.TEXT_DIM)
		draw_string(font, Vector2(6, ed.RULER_H - 7), "bones / frames", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UI.TEXT_DIM)
		# The rows.
		var rows: Array = ed.rows()
		var dk := Vector2(5, 0)
		for i in visible_rows():
			var b := top_row + i
			if b >= rows.size():
				break
			var y: float = ed.RULER_H + i * ed.ROW_H
			if b == ed.bone:
				draw_rect(Rect2(0, y, size.x, ed.ROW_H), Color(NeonTheme.CYAN, 0.22))
			elif i % 2 == 1:
				draw_rect(Rect2(0, y, size.x, ed.ROW_H), Color(1, 1, 1, 0.025))
			draw_string(font, Vector2(6, y + ed.ROW_H - 5), ed._bone_name(b), HORIZONTAL_ALIGNMENT_LEFT, ed.NAME_W - 10, fs,
				NeonTheme.PINK if b == ed.bone else NeonTheme.TEXT)
			var cy: float = y + ed.ROW_H * 0.5
			for f in rows[b]:
				if f >= n:
					continue
				var picked: bool = ed.sel_keys.has(Vector2i(b, f))
				var x := fx(f + (_by if picked and _press == "keys" else 0))
				var r := 5.0 if picked else 4.0
				draw_colored_polygon(PackedVector2Array([Vector2(x, cy - r), Vector2(x + r, cy), Vector2(x, cy + r), Vector2(x - r, cy)]),
					NeonTheme.PINK if picked else Color(0.85, 0.75, 0.6))
		draw_line(Vector2(ed.NAME_W, 0), Vector2(ed.NAME_W, size.y), Color(NeonTheme.CYAN, 0.4))

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN or mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				top_row = clampi(top_row + (2 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -2), 0, maxi(0, ed.rows().size() - visible_rows()))
				queue_redraw()
				accept_event()
				return
			if mb.button_index != MOUSE_BUTTON_LEFT:
				return
			accept_event()
			if mb.position.y < ed.RULER_H:
				_press = "scrub"
				ed.playing = false
				ed.set_frame(frame_at(mb.position.x))
				return
			var b := row_at(mb.position.y)
			if b < 0:
				return
			if mb.position.x < ed.NAME_W:
				ed.select_bone(b)
				return
			var f := frame_at(mb.position.x)
			var hit: bool = (ed.rows()[b] as PackedInt32Array).has(f) and absf(fx(f) - mb.position.x) <= 7.0
			if hit:
				var v := Vector2i(b, f)
				if mb.shift_pressed:
					if ed.sel_keys.has(v):
						ed.sel_keys.erase(v)
					else:
						ed.sel_keys[v] = true
				elif not ed.sel_keys.has(v):
					ed.sel_keys = {v: true}
				ed.bone = b
				ed._sync_bone_fields()
				ed._redraw()
				if not ed.sel_keys.is_empty():
					_press = "keys"
					_from = mb.position
					_by = 0
			else:
				if not mb.shift_pressed:
					ed.sel_keys.clear()
				ed.select_bone(b)
				ed.playing = false
				ed.set_frame(f)
			queue_redraw()
		elif mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _press == "keys" and _by != 0:
				var by := _by
				_by = 0
				ed.move_keys(by)
			_press = ""
			_by = 0
			queue_redraw()
		var mm := event as InputEventMouseMotion
		if mm:
			if _press == "scrub":
				ed.set_frame(frame_at(mm.position.x))
			elif _press == "keys":
				var by := roundi((mm.position.x - _from.x) / px())
				if by != _by:
					_by = by
					queue_redraw()


## The playhead (its own layer: the sheet isn't drawn again as it moves).
class Head extends Control:
	var sheet

	func _draw() -> void:
		var ed = sheet.ed
		if ed.frames() <= 0:
			return
		var x: float = sheet.fx(ed.time * ed._fps) if ed.playing else sheet.fx(ed.frame)
		draw_line(Vector2(x, 0), Vector2(x, size.y), NeonTheme.CYAN, 2.0)
		draw_rect(Rect2(x - 12, 2, 24, ed.RULER_H - 4), NeonTheme.CYAN)
		var s := str(ed.frame)
		var font := get_theme_default_font()
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, ed.FS).x
		draw_string(font, Vector2(x - w * 0.5, ed.RULER_H - 7), s, HORIZONTAL_ALIGNMENT_LEFT, -1, ed.FS, NeonTheme.INK)
