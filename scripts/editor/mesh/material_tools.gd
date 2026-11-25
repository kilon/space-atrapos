extends Node
## The mesh editor's materials (a node of the editor, `ed`): the material library and its
## browser (the Materials tab), the MATERIAL panel on the right - the picked material's settings
## with a live preview ball - and giving materials to surfaces (double-click, the Assign button,
## a drag into the view; in edit mode, to the selected faces: split into a surface of their own).
## An edit applies at once to every surface of the open model that uses the material, and is
## one undo step (a slider dragged: one step). Saved with the model - a character's materials
## into its model.json (the "mesh_editor_own" ones: _write_material_table), your library
## materials into data/materials.json (or your mod's merge file).
## A library material given to the open model becomes one Material shared by every surface it's
## given to (meta "mat_lib_id"): editing the library entry edits that Material too.

const MaterialLibrary := preload("res://scripts/editor/mesh/material_library.gd")
const MaterialBrowser := preload("res://scripts/editor/mesh/material_browser.gd")
const MeshThumbs := preload("res://scripts/editor/mesh/mesh_thumbs.gd")
const MeshIO := preload("res://scripts/editor/mesh/mesh_io.gd")
## The settings a character's material has (the rest: a full material's).
const CHAR_ROWS := ["color", "metal", "rough", "emit"]
const CHAR_NOTE := "A character's material carries only its colour, metal, roughness and glow: the game merges a character\ninto one surface with one shader and reads these from its model.json by the material's name."
const THUMB_DELAY_MS := 400
const PREVIEW := 112

var ed: Control
var lib: MaterialLibrary
var browser: MaterialBrowser
var thumbs: Node
## The material shown in the MATERIAL panel ("": none).
var picked := ""
var _linked := {}          # library id -> the Material it is in the open model
var _model_sig := ""
var _rows := {}            # setting -> its row
var _ctl := {}             # setting -> its control
var _tips := {}            # setting -> its tooltip (a character's note added when it is one)
var _tex := {}             # slot -> {thumb, replace, clear}
var _name_l: Label
var _info_l: Label
var _preview: TextureRect
var _vp: SubViewport
var _ball: MeshInstance3D
var _pv_mat: Material       # the preview's material (a library one not in the model: a copy of its own)
var _pv_due := false
var _thumb_due := {}
var _thumb_at := 0
var _syncing := false
var _serial := 0            # (each pick: slider drags coalesce into one undo step only within it)
var _dialog: FileDialog


func setup(editor: Control) -> void:
	ed = editor
	name = "MaterialTools"
	thumbs = MeshThumbs.new()
	thumbs.name = "MaterialThumbs"
	add_child(thumbs)
	lib = MaterialLibrary.new()
	lib.load_all()
	browser = MaterialBrowser.new()
	browser.name = "MaterialBrowser"
	browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.setup(lib, thumbs)
	browser.picked.connect(pick)
	browser.activated.connect(func(id): assign_selected(id))
	browser.action.connect(_action)
	_build_preview()


func _build_preview() -> void:
	_vp = SubViewport.new()
	_vp.name = "MaterialPreview"
	_vp.size = Vector2i(PREVIEW, PREVIEW)
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.65)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40, 35, 0)
	key.light_energy = 1.6
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_energy = 0.8
	rim.light_color = Color(0.7, 0.8, 1.0)
	_vp.add_child(rim)
	var cam := Camera3D.new()
	cam.fov = 32.0
	_vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.25, 1.9), Vector3.ZERO, Vector3.UP)
	_ball = MeshInstance3D.new()
	_ball.mesh = MaterialLibrary.sphere_mesh(MaterialLibrary.sphere_arrays(), null)
	_vp.add_child(_ball)


func _process(_dt: float) -> void:
	if _pv_due:
		_pv_due = false
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	if not _thumb_due.is_empty() and Time.get_ticks_msec() >= _thumb_at:
		for id in _thumb_due:
			if lib.has(id):
				browser.update_item(id)
		_thumb_due.clear()


## The MATERIAL section's settings (under the editor's surface list), into `box`.
func build_right(box: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	box.add_child(head)
	_preview = TextureRect.new()
	_preview.name = "MaterialPreviewBall"
	_preview.custom_minimum_size = Vector2(PREVIEW, PREVIEW) * 0.75
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture = _vp.get_texture()
	_preview.mouse_filter = Control.MOUSE_FILTER_STOP
	_preview.tooltip_text = EditorIcons.tip("Material preview", "", "The picked material on a ball, lit as the editor's view is - drawn again as you change it.")
	head.add_child(_preview)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(col)
	_name_l = UI.label("(no material picked)", 14, NeonTheme.HEAD)
	_name_l.clip_text = true
	_name_l.mouse_filter = Control.MOUSE_FILTER_STOP
	_name_l.tooltip_text = EditorIcons.tip("Material being edited", "", "The material being edited: the selected surface's, or the one picked in the Materials tab.")
	col.add_child(_name_l)
	_info_l = UI.label("", 13, UI.TEXT_DIM)
	_info_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_l.custom_minimum_size.x = 100
	_info_l.mouse_filter = Control.MOUSE_FILTER_STOP
	col.add_child(_info_l)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 2)
	box.add_child(rows)
	var color := ColorPickerButton.new()
	color.custom_minimum_size = Vector2(80, 24)
	color.color_changed.connect(func(c: Color): set_value("color", [c.r, c.g, c.b, c.a]))
	_row(rows, "color", "Colour", color, EditorIcons.tip("Albedo colour", "", "The material's base colour (with its opacity, when Transparency is on)."))
	_tex_row(rows, "albedo", "Albedo map", "Albedo texture", "A picture over the base colour (the colour tints it).")
	for p in [["metal", "Metallic", 1.0, "How metallic: 0 paint, stone, cloth; 1 bare metal."], ["rough", "Roughness", 1.0, "0 mirror-smooth, 1 matt."]]:
		_row(rows, p[0], p[1], _slider(p[0], p[2]), EditorIcons.tip(p[1], "", p[3]))
	_tex_row(rows, "rough", "Rough map", "Roughness texture", "A picture of how rough each spot is (its grey: black smooth, white matt) - times Roughness.")
	_row(rows, "emit", "Glow", _slider("emit", 8.0), EditorIcons.tip("Glow", "", "How brightly it glows (0: not at all) - a character's in its own colour."))
	var emc := ColorPickerButton.new()
	emc.custom_minimum_size = Vector2(80, 24)
	emc.edit_alpha = false
	emc.color_changed.connect(func(c: Color): set_value("emission", [c.r, c.g, c.b]))
	_row(rows, "emission", "Glow colour", emc, EditorIcons.tip("Glow colour", "", "The colour it glows in (with Glow above 0)."))
	_tex_row(rows, "emission", "Glow map", "Glow texture", "A picture of where it glows, and in what colour.")
	_tex_row(rows, "normal", "Normal map", "Normal map", "A normal map: small bumps and dents drawn into the light without changing the mesh.")
	_row(rows, "normal", "Bumps", _slider("normal", 4.0), EditorIcons.tip("Normal map strength", "", "How deep the normal map's bumps look (1: as drawn)."))
	var alpha := CheckBox.new()
	alpha.text = "See-through"
	alpha.focus_mode = Control.FOCUS_NONE
	alpha.add_theme_font_size_override("font_size", 14)
	alpha.toggled.connect(func(on): set_value("alpha", on))
	_row(rows, "alpha", "Alpha", alpha, EditorIcons.tip("Transparency", "", "The colour's opacity (and the albedo texture's) makes it see-through - glass, a visor, a hologram."))
	var uvb := HBoxContainer.new()
	uvb.add_theme_constant_override("separation", 2)
	for a in 2:
		var sp := SpinBox.new()
		sp.min_value = 0.01
		sp.max_value = 100.0
		sp.step = 0.01
		sp.allow_greater = true
		sp.custom_minimum_size.x = 60
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.tooltip_text = EditorIcons.tip("UV scale " + "UV"[a], "", "How many times the textures repeat across the surface, %s." % ["along U (across)", "along V (up)"][a])
		sp.value_changed.connect(func(_v): _uv_changed())
		uvb.add_child(sp)
		_ctl["uv%d" % a] = sp
	_row(rows, "uv", "UV scale", uvb, EditorIcons.tip("UV scale", "", "How many times the textures repeat across the surface (U, V)."))
	var cull := OptionButton.new()
	cull.focus_mode = Control.FOCUS_NONE
	cull.add_theme_font_size_override("font_size", 14)
	for t in ["Back hidden", "Front hidden", "Both sides"]:
		cull.add_item(t)
	cull.item_selected.connect(func(i): set_value("cull", MaterialLibrary.CULLS[i]))
	_row(rows, "cull", "Sides", cull, EditorIcons.tip("Cull mode", "", "Which side of each face is drawn: the front only (the usual), the back only, or both (thin\nthings seen from both sides - leaves, cloth, flags)."))
	_show()


func _slider(key: String, mx: float) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = mx
	s.step = 0.01
	s.custom_minimum_size = Vector2(90, 20)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(v): set_value(key, v))
	return s


func _row(rows: VBoxContainer, key: String, label: String, c: Control, tip: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var l := UI.label(label, 14, UI.TEXT_DIM)
	l.custom_minimum_size.x = 84
	l.clip_text = true
	h.add_child(l)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(c)
	rows.add_child(h)
	_rows[key] = h
	if not _ctl.has(key):
		_ctl[key] = c
	_tips[key] = tip
	c.tooltip_text = tip


func _tex_row(rows: VBoxContainer, slot: String, short: String, label: String, help: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	var l := UI.label(short, 14, UI.TEXT_DIM)
	l.custom_minimum_size.x = 84
	l.clip_text = true
	h.add_child(l)
	var tr := TextureRect.new()
	tr.custom_minimum_size = Vector2(30, 30)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.tooltip_text = EditorIcons.tip(label, "", help + "\n(none: the square stays empty)")
	h.add_child(tr)
	var rep := UI.button("Replace", func(): _pick_picture(slot), 13)
	rep.focus_mode = Control.FOCUS_NONE
	rep.tooltip_text = EditorIcons.tip("Replace " + label.to_lower(), "", help + "\nPicks a picture of yours (PNG, JPG, WebP): it's copied into the game or your mod\n(art/materials/) when the library or the model is saved.")
	rep.visible = not OS.has_feature("web")
	h.add_child(rep)
	var clr := UI.button("Clear", func(): set_texture_image(slot, null), 13)
	clr.focus_mode = Control.FOCUS_NONE
	clr.tooltip_text = EditorIcons.tip("Clear " + label.to_lower(), "", "Takes the picture off the material.")
	h.add_child(clr)
	rows.add_child(h)
	_rows["tex_" + slot] = h
	_tex[slot] = {"thumb": tr, "replace": rep, "clear": clr}
	_tips["tex_" + slot] = tr.tooltip_text


# --- the open model ------------------------------------------------------------------------

func _is_char() -> bool:
	return MeshIO.is_character(str(ed.path))


## The open model's materials as the library's "This model" group (when they changed).
func refresh_model() -> void:
	var mats := []
	for p: MeshInstance3D in ed.parts():
		for i in p.mesh.get_surface_count():
			var m := p.get_surface_override_material(i)
			if m == null:
				m = p.mesh.surface_get_material(i)
			if m and not m in mats:
				mats.append(m)
	var sig := str(ed.path) + "|" + ",".join(mats.map(func(m): return str(m.get_instance_id()) + m.resource_name))
	if sig == _model_sig:
		return
	_model_sig = sig
	lib.set_model(mats, _is_char())
	for id in _linked.keys():
		if not is_instance_valid(_linked[id]) or not _linked[id] in mats:
			_linked.erase(id)
	for m: Material in mats:
		var lid := str(m.get_meta("mat_lib_id", ""))
		if lid != "" and lib.has(lid):
			_linked[lid] = m
	if picked != "" and not lib.has(picked):
		picked = ""
		_show()
	if browser.is_visible_in_tree():
		browser.refill()


## The editor opened another model: the old one's links forgotten.
func model_changed() -> void:
	_linked.clear()
	_model_sig = "-"
	refresh_model()


## Surface `s` of part `p` selected: its material shown.
func show_surface(p: MeshInstance3D, s: int) -> void:
	refresh_model()
	var m: Material = null
	if p and s >= 0 and s < p.mesh.get_surface_count():
		m = p.get_surface_override_material(s)
		if m == null:
			m = p.mesh.surface_get_material(s)
	pick("model:%d" % m.get_instance_id() if m else "")


## The open model's materials that are library entry `id`'s.
func _mats_of(id: String) -> Array:
	var out := []
	if _linked.has(id) and is_instance_valid(_linked[id]):
		out.append(_linked[id])
	for mid in lib.ids("model"):
		var m: Material = lib.entry(mid)["mat"]
		if str(m.get_meta("mat_lib_id", "")) == id and not m in out:
			out.append(m)
	return out


# --- picking and editing -------------------------------------------------------------------

func pick(id: String) -> void:
	if id != "" and not lib.has(id):
		id = ""
	picked = id
	_serial += 1
	_pv_mat = null
	_show()


## The settings showing in the panel now (the rows visible) - a character's: colour, metal, roughness, glow.
func shown_settings() -> Array:
	var out := []
	for k in _rows:
		if (_rows[k] as Control).visible:
			out.append(k)
	return out


func _show() -> void:
	if _name_l == null:
		return
	_syncing = true
	var e := lib.entry(picked)
	var on := not e.is_empty()
	var editable := lib.is_editable(picked)
	var char: bool = on and e["kind"] == "character"
	_name_l.text = str(e["name"]) if on else "(no material picked)"
	var info := ""
	var tip := ""
	if on:
		info = "%s · %s" % [MaterialLibrary.GROUP_LABEL[e["group"]], "character" if char else "full"]
		var slot := MaterialLibrary.slot_of(str(e["name"]))
		if char:
			info += " · recolour slot: " + slot if slot != "" else " · fixed colour"
			tip = CHAR_NOTE + ("\nNamed %s, it takes the colour a character is recoloured with (%s)." % [e["name"], slot] if slot != "" else "")
		if not e.get("users", []).is_empty():
			tip += "\nWorn by: " + ", ".join(e["users"])
		if not editable:
			info += " · built in" if e["group"] != "model" else " · a shader of its own"
			tip += "\n" + ("A built-in look: Duplicate it (the Materials tab) to make one of your own to change." if e["group"] != "model" else "Its own shader: not editable here.")
	_info_l.text = info
	_info_l.tooltip_text = EditorIcons.tip("About this material", "", tip.strip_edges() if tip.strip_edges() != "" else "Its group and kind.")
	for k in _rows:
		(_rows[k] as Control).visible = on and (not char or k in CHAR_ROWS)
	var v := lib.values(picked)
	var c: Array = v["color"]
	var cp: ColorPickerButton = _ctl["color"]
	cp.edit_alpha = not char
	cp.color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
	for k in ["metal", "rough", "emit", "normal"]:
		(_ctl[k] as Range).set_value_no_signal(float(v[k]))
	var ec: Array = v["emission"]
	(_ctl["emission"] as ColorPickerButton).color = Color(ec[0], ec[1], ec[2])
	(_ctl["alpha"] as CheckBox).set_pressed_no_signal(bool(v["alpha"]))
	for a in 2:
		(_ctl["uv%d" % a] as SpinBox).set_value_no_signal(float(v["uv"][a]))
	(_ctl["cull"] as OptionButton).select(maxi(MaterialLibrary.CULLS.find(str(v["cull"])), 0))
	for k in _ctl:
		var ctl: Control = _ctl[k]
		if ctl is BaseButton:
			(ctl as BaseButton).disabled = not editable
		elif ctl is Range:
			(ctl as Range).editable = editable
		var base: String = _tips.get(k, ctl.tooltip_text if not _tips.has(k) else "")
		if _tips.has(k):
			ctl.tooltip_text = base + ("\n" + CHAR_NOTE if char else "") + ("" if editable or not on else "\n(built in: Duplicate it to change it)")
	var tx := lib.textures(picked)
	for s in _tex:
		var r: Dictionary = _tex[s]
		(r["thumb"] as TextureRect).texture = tx.get(s)
		(r["replace"] as Button).disabled = not editable
		(r["clear"] as Button).disabled = not editable or not tx.has(s)
	_syncing = false
	_update_preview()


func _update_preview() -> void:
	var e := lib.entry(picked)
	if e.is_empty():
		_ball.material_override = null
		_ball.visible = false
	else:
		_ball.visible = true
		var m: Material = null
		if e["group"] == "model":
			m = e["mat"]
		elif _linked.has(picked) and is_instance_valid(_linked[picked]):
			m = _linked[picked]
		else:
			if _pv_mat == null:
				_pv_mat = lib.make_material(picked)
			else:
				MaterialLibrary.apply(_pv_mat, str(e["kind"]), lib.values(picked), e["textures"])
			m = _pv_mat
		_ball.material_override = m
	_pv_due = true


func _uv_changed() -> void:
	set_value("uv", [(_ctl["uv0"] as SpinBox).value, (_ctl["uv1"] as SpinBox).value])


## Sets one setting of the picked material - on every surface using it; one undo step (a
## slider dragged: one step).
func set_value(key: String, v: Variant) -> void:
	if _syncing or picked == "" or not lib.is_editable(picked):
		return
	var id := picked
	var before := lib.values(id)
	var after := before.duplicate(true)
	after[key] = v
	_apply(id, after)
	_step("Material " + key, func(): _apply(id, before), func(): _apply(id, after), "%d|%s|%s" % [_serial, id, key])


## One undo step (in edit mode: of the edit's own steps); `tag` the same as the last's: that
## step's redo replaced (a slider dragged).
func _step(nm: String, undo_it: Callable, redo_it: Callable, tag := "") -> void:
	var editing: bool = ed.mode == "edit"
	var stack: Array = ed._eundo if editing else ed._undo
	if tag != "" and not stack.is_empty() and str(stack.back().get("mat_tag", "")) == tag:
		stack.back()["redo"] = redo_it
		ed.dirty = true
		return
	if editing:
		ed._eundo.append({"name": nm, "undo": undo_it, "redo": redo_it, "mat_tag": tag})
		ed._eredo.clear()
		ed.dirty = true
		ed._update_ui()
	else:
		ed._push(nm, undo_it, redo_it)
		ed._undo.back()["mat_tag"] = tag


## Material `id` given settings `vals` (`tex`: its textures too - slot -> Texture2D for a model's,
## slot -> res path for yours; null: as they are) - and every surface using it.
func _apply(id: String, vals: Dictionary, tex: Variant = null) -> void:
	var e := lib.entry(id)
	if e.is_empty():
		return
	var changed := [id]
	if e["group"] == "model":
		var m: Material = e["mat"]
		MaterialLibrary.apply(m, str(e["kind"]), vals, tex)
		m.set_meta("mesh_editor_own", true)
		var lid := str(m.get_meta("mat_lib_id", ""))
		if lid != "" and lib.entry(lid).get("group", "") == "mine":
			lib.set_values(lid, vals)
			changed.append(lid)
	else:
		lib.set_values(id, vals)
		if tex is Dictionary:
			lib.set_textures(id, tex)
		for m: Material in _mats_of(id):
			MaterialLibrary.apply(m, str(e["kind"]), vals, lib.entry(id)["textures"])
			if _is_char():
				m.set_meta("mesh_editor_own", true)
			changed.append("model:%d" % m.get_instance_id())
	for c in changed:
		_thumb_due[c] = true
	_thumb_at = Time.get_ticks_msec() + THUMB_DELAY_MS
	if picked in changed:
		_show()
	ed.view.request()


## A picture for texture `slot` of the picked material (null: the texture taken off) - undoable.
func set_texture_image(slot: String, img: Image) -> void:
	if picked == "" or not lib.is_editable(picked):
		return
	var id := picked
	var e := lib.entry(id)
	var before: Dictionary
	var after: Dictionary
	if e["group"] == "model":
		before = lib.textures(id)
		after = before.duplicate()
		if img:
			img.generate_mipmaps()
			after[slot] = ImageTexture.create_from_image(img)
		else:
			after.erase(slot)
	else:
		before = (e["textures"] as Dictionary).duplicate()
		after = before.duplicate()
		if img:
			var res := lib.texture_path(id, slot)
			lib.keep_picture(res, img)
			after[slot] = res
		else:
			after.erase(slot)
	_apply(id, lib.values(id), after)
	_step("Material texture", func(): _apply(id, lib.values(id), before), func(): _apply(id, lib.values(id), after))


func _pick_picture(slot: String) -> void:
	if _dialog:
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Pictures"])
	_dialog.use_native_dialog = true
	add_child(_dialog)
	_dialog.file_selected.connect(func(path: String):
		var img := Image.load_from_file(path)
		if img == null:
			ed._say("Couldn't read " + path.get_file())
			return
		set_texture_image(slot, img))
	_dialog.popup_centered(Vector2i(900, 600))


# --- giving materials to surfaces ----------------------------------------------------------

## The Material library entry `id` is in the open model (made once, shared by every surface
## it's given to; a character's own material of that name, if it has one).
func material_for(id: String) -> Material:
	var e := lib.entry(id)
	if e.is_empty():
		return null
	if e["group"] == "model":
		return e["mat"]
	if _linked.has(id) and is_instance_valid(_linked[id]):
		return _linked[id]
	if _is_char():
		for mid in lib.ids("model"):
			var own: Material = lib.entry(mid)["mat"]
			if own.resource_name == str(e["name"]):
				return own
	var m := lib.make_material(id)
	if _is_char():
		m.set_meta("mesh_editor_own", true)   # (written into its model.json when saved)
	_linked[id] = m
	return m


## Gives material `id` to surface `s` of part `p` (undoable).
func assign(id: String, p: MeshInstance3D, s: int) -> void:
	var m := material_for(id)
	if m == null or p == null:
		return
	ed.set_surface_material(p, s, m)
	refresh_model()
	ed._say("%s given to %s's surface %d." % [lib.entry(id)["name"], p.name, s + 1])


## Gives material `id` (""): the browser's pick, else the panel's) to the selected faces (edit
## mode), else to the selected part's surface.
func assign_selected(id := "") -> void:
	if id == "":
		id = browser.selected() if browser.selected() != "" else picked
	if id == "" or not lib.has(id):
		ed._say("Pick a material in the Materials tab first.")
		return
	if ed.mode == "edit" and ed.em and ed.sel_t.has(1):
		assign_faces(id)
		return
	if ed.part == null:
		ed._say("Select a part first: the material goes to its surface (the MATERIAL panel's Surface).")
		return
	assign(id, ed.part, maxi(ed._surface_index(), 0))


## Edit mode: material `id` given to the selected faces - split into a surface of their own if
## they're only some of theirs (one edit step).
func assign_faces(id: String) -> void:
	var em = ed.em
	if em == null:
		return
	var ts: PackedByteArray = em.grow_to_polys(ed.sel_t.duplicate())
	if not ts.has(1):
		ed._say("Select faces first.")
		return
	var m := material_for(id)
	var before: Dictionary = ed._snap()
	var now: PackedByteArray = em.split_to_surface(ts, m)
	ed._resize_sel()
	ed.select_all(false)
	for t in mini(now.size(), ed.sel_t.size()):
		ed.sel_t[t] = now[t]
	ed._derive_sel()
	ed._edit_done("Material", before)
	ed._show_material_list()
	refresh_model()
	var n := _count(now)
	ed._say("%s given to the selected faces (%d triangle%s)." % [lib.entry(id)["name"], n, "" if n == 1 else "s"])


static func _count(sel: PackedByteArray) -> int:
	var n := 0
	for b in sel:
		n += b
	return n


## The part, surface and triangle under `at` in the view ([] - none).
func surface_at(at: Vector2) -> Array:
	var r: Array = ed.view.ray(at)
	var best := INF
	var out := []
	for p: MeshInstance3D in ed.parts():
		if not p.is_visible_in_tree():
			continue
		var tm := p.mesh.generate_triangle_mesh()
		if tm == null:
			continue
		var inv := p.global_transform.affine_inverse()
		var h := tm.intersect_ray(inv * (r[0] as Vector3), (inv.basis * (r[1] as Vector3)).normalized())
		if h.is_empty():
			continue
		var d: float = (p.global_transform * (h["position"] as Vector3)).distance_to(r[0])
		if d < best:
			best = d
			out = [p, _surface_of(p.mesh, int(h.get("face_index", 0))), int(h.get("face_index", 0))]
	return out


## The surface triangle `fi` of the mesh's faces (as Mesh.get_faces() lists them) is in.
static func _surface_of(m: Mesh, fi: int) -> int:
	for s in m.get_surface_count():
		if m.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var n := 0
		if m is ArrayMesh:
			var am := m as ArrayMesh
			n = am.surface_get_array_index_len(s)
			if n <= 0:
				n = am.surface_get_array_len(s)
		else:
			var a := m.surface_get_arrays(s)
			n = (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if a[Mesh.ARRAY_INDEX] != null else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		n /= 3
		if fi < n:
			return s
		fi -= n
	return maxi(m.get_surface_count() - 1, 0)


func can_drop(data: Variant) -> bool:
	return data is Dictionary and data.has("mesh_material") and lib.has(str(data["mesh_material"]))


## A material dropped on the view: given to the surface under it (in edit mode, onto a selected
## face: to the selected faces).
func drop(at: Vector2, data: Variant) -> void:
	var id := str(data["mesh_material"])
	var hit := surface_at(at)
	if hit.is_empty():
		ed._say("Drop a material on a surface of the model.")
		return
	var p: MeshInstance3D = hit[0]
	if ed.mode == "edit" and p == ed.part and int(hit[2]) < ed.sel_t.size() and ed.sel_t[int(hit[2])]:
		assign_faces(id)
		return
	if ed.mode != "edit" and p != ed.part:
		ed.select_part(p)
	assign(id, p, int(hit[1]))


# --- the library's buttons -----------------------------------------------------------------

func _action(what: String) -> void:
	match what:
		"new": new_material()
		"duplicate": duplicate_material()
		"rename": rename_dialog()
		"delete": delete_material()


func _sel() -> String:
	return browser.selected() if browser.selected() != "" else picked


func _added(id: String) -> void:
	save_library()
	if browser.group != "" and browser.group != "mine":
		browser.set_group("mine")
	else:
		browser.refill()
	browser.select_id(id)
	pick(id)


## A new material of yours (a character's kind when a character is open); its id.
func new_material() -> String:
	var id := lib.add("New material", "character" if _is_char() else "standard", MaterialLibrary.defaults())
	_added(id)
	ed._say("A new material (Mine): change it in the MATERIAL panel, then double-click it or drag it onto a surface.")
	return id


## A copy of the picked material as yours; its id.
func duplicate_material() -> String:
	var src := _sel()
	if src == "":
		ed._say("Pick a material to duplicate.")
		return ""
	var id := lib.duplicate_entry(src)
	_added(id)
	ed._say("Duplicated as %s (Mine)." % lib.entry(id)["name"])
	return id


func rename_dialog() -> void:
	var id := _sel()
	if id == "":
		return
	if lib.entry(id)["group"] != "mine":
		ed._say("Only your own materials can be renamed (a character's are found by their names; duplicate a built-in look to name your own).")
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.name = "MaterialDialog"
	ed.add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var box := UI.modal(root, Color(1.0, 0.72, 0.38), Vector2(520, 0))
	box.add_child(UI.label("Rename material", 24, NeonTheme.HEAD))
	var le := LineEdit.new()
	le.text = str(lib.entry(id)["name"])
	le.custom_minimum_size.x = 360
	le.add_theme_font_size_override("font_size", 16)
	le.tooltip_text = EditorIcons.tip("Material name", "Enter", "Its new name (a character's table keeps a material by its name).")
	box.add_child(le)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var ok := func():
		var n := le.text.strip_edges()
		if n == "":
			return
		layer.queue_free()
		rename_material(id, n)
	le.text_submitted.connect(func(_t): ok.call())
	var cancel := UI.button("Cancel", layer.queue_free, 16)
	cancel.tooltip_text = EditorIcons.tip("Cancel", "Esc", "Keeps its name.")
	row.add_child(cancel)
	var keep := UI.button("Rename", ok, 16)
	keep.tooltip_text = EditorIcons.tip("Rename", "Enter", "Gives it the new name.")
	row.add_child(keep)
	le.grab_focus.call_deferred()


func rename_material(id: String, n: String) -> void:
	lib.rename(id, n)
	for m: Material in _mats_of(id):
		m.resource_name = n
	save_library()
	browser.refill()
	browser.select_id(id)
	_show()


## Removes the picked material from the library (yours; a built-in look only in a mod, asked first).
func delete_material(confirmed := false) -> void:
	var id := _sel()
	if id == "":
		return
	var e := lib.entry(id)
	if e["group"] == "model":
		ed._say("A material of the model itself: give its surfaces another material instead.")
		return
	if lib.is_builtin(id):
		if not EditTarget.is_mod():
			ed._say("The game's own looks can be removed only in a mod (Mods > Mod Editor): duplicate one to make your own.")
			return
		if not confirmed:
			UI.confirm(ed, "Remove a built-in look?", "%s is one of the game's looks. Remove it from the material library in your mod?" % e["name"],
				func(): delete_material(true), "Remove", "Cancel")
			return
	lib.remove(id)
	_linked.erase(id)
	save_library()
	if picked == id:
		pick("")
	browser.refill()
	ed._say("Removed the material %s from the library (surfaces that have it keep it)." % e["name"])


## Writes the library (your materials, the pictures picked) if it changed. OK or an error.
func save_library() -> int:
	if not lib.dirty and lib.pending.is_empty():
		return OK
	var err := lib.save()
	if err != OK:
		ed._say("Couldn't save the material library (%s)." % error_string(err))
	return err
