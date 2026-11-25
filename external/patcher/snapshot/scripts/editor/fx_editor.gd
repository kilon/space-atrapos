extends Control
## Talos's effects editor (Talos > Effects, F4): the game's particle effects
## (data/effects.json - Fx). On the left the effects (new, duplicate, rename,
## delete); in the middle a 3D view playing the one picked (a one-shot replayed
## again and again, a looping one running; orbit, zoom, a ground under it or
## space); on the right its parameters (FxParams: the effect's own, its flash of
## light, every emitter's - sliders, min-max pairs, colour ramps, a scale curve).
## Every edit changes the definition the game uses (Fx.set_def): the view and any
## game running under Talos show it at once. Undo / redo (Ctrl+Z / Ctrl+Shift+Z)
## take whole steps of the effects; Save (Ctrl+S) writes data/effects.json through
## EditTarget - into the game, or the mod the Mod Editor is on.

const ACCENT := Color(1.0, 0.62, 0.3)
const UNDO_MAX := 200
## Edits to one value closer than this (s) are one undo step (a slider's drag).
const MERGE_S := 0.8

var embedded := false
var dirty := false
var current := ""
var loop_play := true
var ground := false
var preview_scale := 1.0

var _undo: Array = []
var _redo: Array = []
var _last_key := ""
var _last_t := 0
var _built := false
var _fx: Fx
var _gap := 0.0

var _note: Label
var _save_btn: Button
var _undo_btn: Button
var _redo_btn: Button
var _list: ItemList
var _name_edit: LineEdit
var _params: FxParams
var _vp: SubViewport
var _cam: Camera3D
var _stage: Node3D
var _ground: MeshInstance3D
var _view: Control
var yaw := 0.6
var pitch := 0.3
var dist := 40.0


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build()
	var names := Fx.names()
	select("explosion" if names.has("explosion") else (str(names[0]) if not names.is_empty() else ""))


# --- The screen ------------------------------------------------------------------

func _build() -> void:
	var col: VBoxContainer
	if embedded:
		col = VBoxContainer.new()
		col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
		col.add_theme_constant_override("separation", 8)
		add_child(col)
	else:
		col = TalosNav.wrap(UI.modal(self, ACCENT, Vector2.ZERO, true), "fx", func(id): TalosNav.go(get_tree(), id, guard))
	var hd: Array = TalosNav.header("EFFECTS", "", ACCENT)
	var header: HBoxContainer = hd[0]
	_note = hd[1]
	_save_btn = _btn("Save", "save", "Ctrl+S", "Writes every effect to data/effects.json - into the game,\nor into your mod in the Mod Editor.", save)
	header.add_child(_save_btn)
	_undo_btn = _btn("Undo", "undo", "Ctrl+Z", "Takes back the last edit.", undo)
	header.add_child(_undo_btn)
	_redo_btn = _btn("Redo", "redo", "Ctrl+Shift+Z", "Does again what Undo took back.", redo)
	header.add_child(_redo_btn)
	header.add_child(EditorIcons.docs_button(self, "fx"))
	col.add_child(header)
	var row := HBoxContainer.new()
	row.size_flags_vertical = SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	row.add_child(_build_list())
	row.add_child(_build_view())
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 470
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_params = FxParams.new()
	_params.name = "Params"
	_params.before_edit.connect(_before_edit)
	_params.changed.connect(_after_edit)
	scroll.add_child(_params)
	if not embedded:
		UI.scale_fonts(col, "menu", 1.2)
	_built = true
	_refresh_header()


func _build_list() -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 240
	box.add_theme_constant_override("separation", 6)
	box.add_child(UI.section("EFFECTS"))
	_list = ItemList.new()
	_list.name = "Effects"
	_list.size_flags_vertical = SIZE_EXPAND_FILL
	_list.focus_mode = FOCUS_NONE
	_list.add_theme_font_size_override("font_size", 14)
	_list.tooltip_text = EditorIcons.tip("Effects", "", "Every particle effect of the game (data/effects.json). Click one to play and edit it.")
	_list.item_selected.connect(func(i): select(str(_list.get_item_metadata(i))))
	box.add_child(_list)
	var row := HBoxContainer.new()
	row.add_child(_btn("New effect", "new", "", "A new effect of your own: one soft glow to start from.", func(): new_effect(false)))
	row.add_child(_btn("Duplicate", "duplicate", "", "A copy of the selected effect, to change as one of your own.", func(): new_effect(true)))
	row.add_child(_btn("Delete effect", "delete", "", "Deletes the selected effect (Undo puts it back). The game's code plays effects by name:\na deleted one it still asks for plays nothing.", delete_effect))
	box.add_child(row)
	var g := HBoxContainer.new()
	g.add_child(UI.label("Name", 14, UI.TEXT_DIM))
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	_name_edit.tooltip_text = EditorIcons.tip("Rename", "Enter", "The effect's name - the game plays its own effects by name, so renaming one of those\nleaves the game asking for the old name.")
	_name_edit.text_submitted.connect(func(t): rename_effect(t); _name_edit.release_focus())
	g.add_child(_name_edit)
	box.add_child(g)
	return box


func _build_view() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_child(_btn("Replay", "play", "Space", "Plays the effect again from its start.", replay))
	var lp := CheckBox.new()
	lp.text = "Loop"
	lp.button_pressed = loop_play
	lp.focus_mode = FOCUS_NONE
	lp.tooltip_text = EditorIcons.tip("Loop", "L", "A one-shot plays again each time it's done.")
	lp.toggled.connect(func(on): loop_play = on)
	lp.name = "LoopCheck"
	row.add_child(lp)
	var gr := CheckBox.new()
	gr.text = "Ground"
	gr.focus_mode = FOCUS_NONE
	gr.tooltip_text = EditorIcons.tip("Ground", "G", "A ground under the effect (dust, a bolt striking a planet); off: space.")
	gr.toggled.connect(func(on): ground = on; _ground.visible = on)
	gr.name = "GroundCheck"
	row.add_child(gr)
	row.add_child(UI.label("Scale", 14, UI.TEXT_DIM))
	var sc := SpinBox.new()
	sc.min_value = 0.05
	sc.max_value = 20.0
	sc.step = 0.05
	sc.value = preview_scale
	sc.tooltip_text = EditorIcons.tip("Preview scale", "", "Plays it this many times its size (as the game scales an explosion to a ship's).\nOnly the view: not saved.")
	sc.value_changed.connect(func(v): preview_scale = v; replay())
	row.add_child(sc)
	row.add_child(_btn("Frame", "fit_all", "F", "Zooms to fit the effect.", frame))
	var hint := UI.label("drag: orbit - wheel: zoom", 13, UI.TEXT_DIM)
	hint.clip_text = true
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
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
	_vp.msaa_3d = Viewport.MSAA_2X
	_vp.positional_shadow_atlas_size = 0
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vpc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.022, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_bloom = 0.1
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 1.4
	_vp.add_child(sun)
	sun.look_at_from_position(Vector3(-3, 5, 4), Vector3.ZERO, Vector3.UP)
	_ground = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	_ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.38, 0.32)
	gm.roughness = 1.0
	_ground.material_override = gm
	_ground.visible = ground
	_vp.add_child(_ground)
	_stage = Node3D.new()
	_stage.name = "Stage"
	_vp.add_child(_stage)
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.05
	_cam.far = 4000.0
	_vp.add_child(_cam)
	_view = View.new()
	(_view as View).ed = self
	_view.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_view.mouse_filter = MOUSE_FILTER_STOP
	holder.add_child(_view)
	_aim()
	return box


func _btn(name: String, icon: String, keys: String, help: String, cb: Callable) -> Button:
	var b := UI.button("", cb, 14)
	b.focus_mode = FOCUS_NONE
	return EditorIcons.dress(b, icon, EditorIcons.tip(name, keys, help))


# --- The effects ------------------------------------------------------------------

func _fill_list() -> void:
	if _list == null:
		return
	_list.clear()
	for n in Fx.names():
		var d := Fx.def(n)
		var i := _list.add_item("%s  (%d)" % [n, (d.get("emitters", []) as Array).size()])
		_list.set_item_metadata(i, n)
		_list.set_item_tooltip(i, str(d.get("about", "")))
		if n == current:
			_list.select(i)


func select(name: String) -> void:
	current = name
	if _name_edit:
		_name_edit.text = name
	_fill_list()
	if _params:
		_params.show_effect(name)
	replay()
	frame()
	_refresh_header()


func _unique(base: String) -> String:
	var n := base
	var k := 2
	while Fx.has(n):
		n = "%s_%d" % [base, k]
		k += 1
	return n


func new_effect(copy: bool) -> void:
	_push("")
	var d: Dictionary
	var n: String
	if copy and current != "":
		d = Fx.def(current).duplicate(true)
		n = _unique(current + "_copy")
	else:
		var e := Fx.new_emitter()
		e["name"] = "glow"
		e["velocity"] = [0.0, 0.0]
		e["scale"] = [3.0, 3.0]
		e["amount"] = 1
		e["lifetime"] = 0.6
		e["colors"] = [[0.0, "#ffd8a0ff"], [1.0, "#ff804000"]]
		e["emissive"] = 2.0
		d = {"about": "", "emitters": [e]}
		n = _unique("effect")
	Fx.set_def(n, d)
	_after_edit()
	select(n)
	_say("new effect: " + n)


func rename_effect(to: String) -> void:
	to = to.strip_edges().replace(" ", "_")
	if current == "" or to == current:
		return
	if to == "" or Fx.has(to):
		_say("can't rename: that name's taken" if to != "" else "")
		_name_edit.text = current
		return
	_push("")
	Fx.rename(current, to)
	if _fx and is_instance_valid(_fx):
		_fx.effect = to
	current = to
	_after_edit()
	_fill_list()


func delete_effect() -> void:
	if current == "":
		return
	_push("")
	var i := Fx.names().find(current)
	Fx.remove(current)
	_after_edit()
	var names := Fx.names()
	select(str(names[clampi(i, 0, names.size() - 1)]) if not names.is_empty() else "")


# --- The view ---------------------------------------------------------------------

## Plays the effect again: a one-shot from its start, a looping one attached.
func replay() -> void:
	if _stage == null:
		return
	if _fx and is_instance_valid(_fx):
		_fx.queue_free()
	_fx = null
	_gap = 0.0
	if current == "" or not Fx.has(current):
		return
	if looping(current):
		_fx = Fx.attach(current, _stage)
		_fx.scale = Vector3.ONE * preview_scale
		_fx.scale_k = preview_scale
	else:
		_fx = Fx.new()
		_fx.effect = current
		_fx.keep = true   # (replayed here: never pooled for the game's use)
		_stage.add_child(_fx)
		_fx.scale = Vector3.ONE * preview_scale
		_fx.scale_k = preview_scale
		_fx.play()


## The effect has emitters that keep emitting.
static func looping(name: String) -> bool:
	for e in Fx.def(name).get("emitters", []):
		if e is Dictionary and not bool(Fx.val(e, "one_shot")):
			return true
	return false


## How far the effect reaches (m, at scale 1): its fastest particles' flight, its biggest.
static func reach(name: String) -> float:
	var r := 1.0
	for e in Fx.def(name).get("emitters", []):
		if not e is Dictionary:
			continue
		var v := Fx._rng2(Fx.val(e, "velocity"))
		var s := Fx._rng2(Fx.val(e, "scale"), Vector2.ONE)
		var dm := Fx._rng2(Fx.val(e, "damping"))
		var life := float(Fx.val(e, "lifetime"))
		var sp := (v.x + v.y) * 0.5
		var fly := sp * life if dm.x <= 0.0 else minf(sp * life, sp * sp / (2.0 * dm.x))
		if str(Fx.val(e, "material")) == "spark":
			fly *= 0.3   # (sparks fly far, thin: framed on the body of it)
		r = maxf(r, float(Fx.val(e, "size")) + fly * 0.7 + s.y * 0.5)
	return r


func frame() -> void:
	dist = clampf(reach(current) * preview_scale * 2.4, 3.0, 1500.0)
	_aim()


func _aim() -> void:
	if _cam == null:
		return
	var at := Vector3(0, reach(current) * preview_scale * 0.25 if ground else 0.0, 0)
	var from := at + Vector3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * dist
	_cam.transform = Transform3D(Basis.looking_at(at - from, Vector3.UP), from)


func _process(delta: float) -> void:
	if _vp:
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE   # (drawn while showing; a parked tool stops processing - and drawing)
	if _fx and is_instance_valid(_fx) and not _fx.attached and not _fx.playing and loop_play:
		_gap += delta
		if _gap > 0.4:
			_gap = 0.0
			_fx.play()


# --- Edits and undo ---------------------------------------------------------------

func _before_edit(key: String) -> void:
	var now := Time.get_ticks_msec()
	if key != "" and key == _last_key and now - _last_t < int(MERGE_S * 1000.0):
		_last_t = now
		return
	_last_key = key
	_last_t = now
	_push(key)


func _push(_key: String) -> void:
	_undo.append({"defs": Fx.snapshot(), "current": current})
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()
	if _key == "":
		_last_key = ""


func _after_edit() -> void:
	dirty = Fx.dirty
	_fill_list()
	_refresh_header()
	_say("")
	if _fx and is_instance_valid(_fx) and looping(current) != _fx.attached:
		replay()


func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append({"defs": Fx.snapshot(), "current": current})
	_restore(_undo.pop_back())
	_say("undone")


func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append({"defs": Fx.snapshot(), "current": current})
	_restore(_redo.pop_back())
	_say("redone")


func _restore(s: Dictionary) -> void:
	Fx.restore(s["defs"])
	_last_key = ""
	dirty = true
	var c := str(s["current"])
	select(c if Fx.has(c) else (str(Fx.names()[0]) if not Fx.names().is_empty() else ""))


func _refresh_header() -> void:
	if _save_btn == null:
		return
	_save_btn.disabled = not EditTarget.writable()
	_undo_btn.disabled = _undo.is_empty()
	_redo_btn.disabled = _redo.is_empty()


func _say(msg: String) -> void:
	if _note:
		_note.text = (msg + "  -  " if msg != "" else "") + "saving into " + EditTarget.label() + ("  (unsaved changes)" if dirty else "")


# --- Saving -----------------------------------------------------------------------

func save() -> bool:
	if not EditTarget.writable():
		_say("can't save here: make a mod (the Mod Editor)")
		return false
	if not Fx.save():
		_say("couldn't write data/effects.json")
		return false
	dirty = false
	_refresh_header()
	_say("saved %d effects" % Fx.names().size())
	return true


## Drops every unsaved edit (the effects as saved).
func discard() -> void:
	Fx.reload_all()
	dirty = false
	_undo.clear()
	_redo.clear()
	select(current if Fx.has(current) else (str(Fx.names()[0]) if not Fx.names().is_empty() else ""))


## Asks about unsaved changes (save / discard / stay), then `next`.
func guard(next: Callable) -> void:
	if not dirty:
		next.call()
		return
	UI.unsaved(self, "The effects editor", func(): save(), discard, next)


## The Mod Editor switched mods: save into the new one (re-read when nothing's unsaved).
func target_changed() -> void:
	if not dirty:
		Fx.reload_all()
		_undo.clear()
		_redo.clear()
		select(current if Fx.has(current) else (str(Fx.names()[0]) if not Fx.names().is_empty() else ""))
	_refresh_header()
	_say("")


func talos_shown() -> void:
	dirty = Fx.dirty
	if _params and current != "":
		_params.show_effect(current)   # (the Live Editor may have changed it meanwhile)
	_fill_list()
	_refresh_header()
	_say("")


# --- Keys -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or has_meta("talos_parked"):
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var handled := true
	if k.ctrl_pressed:
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
			_:
				handled = false
	else:
		match k.keycode:
			KEY_SPACE:
				replay()
			KEY_F:
				frame()
			KEY_L:
				(find_child("LoopCheck", true, false) as CheckBox).button_pressed = not loop_play
			KEY_G:
				(find_child("GroundCheck", true, false) as CheckBox).button_pressed = not ground
			KEY_F1:
				EditorDocs.open(self, "fx")
			KEY_ESCAPE:
				if not embedded:
					get_viewport().set_input_as_handled()   # (before: leaving may free the scene)
					TalosNav.go(get_tree(), "menu", guard)
					return
				handled = false
			_:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()


## The view's mouse: drag to orbit, the wheel to zoom.
class View extends Control:
	var ed
	var _drag := false

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb:
			if mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
				_drag = mb.pressed
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				ed.dist = maxf(0.5, ed.dist * 0.88)
				ed._aim()
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				ed.dist = minf(3000.0, ed.dist / 0.88)
				ed._aim()
			accept_event()
		var mm := event as InputEventMouseMotion
		if mm and _drag:
			ed.yaw -= mm.relative.x * 0.008
			ed.pitch = clampf(ed.pitch + mm.relative.y * 0.008, -1.4, 1.4)
			ed._aim()
			accept_event()
