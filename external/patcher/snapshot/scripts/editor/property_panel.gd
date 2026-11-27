class_name PropertyPanel
extends PanelContainer
## A property inspector for procedural assets (planets, suns, nebulae in the
## zoo). It builds itself from a generator's PROPERTIES list:
##   [key, label, type, min, max, help, modes]   or   ["#", "Group title"]
## Types: float, int, color, vec2, vec3, enum:<a>,<b>,...
## `modes` ([] = always) hides properties that don't apply to the asset's
## current mode (e.g. ocean settings on a gas giant).
## Every edit emits changed(key, value) immediately (live preview). The header
## picks the template and variant and has reset / randomise / copy / close.

signal changed(key: String, value: Variant)
signal template_changed(template: String)
signal variant_changed(variant: int)
signal reset_requested
signal randomize_requested
signal closed
signal undo_requested
signal redo_requested
signal paste_requested
signal apply_all_requested
signal preset_load(name: String)
signal preset_save(name: String, rules: Dictionary)
signal preset_delete(name: String)

const ACCENT := Color(0.4, 0.95, 0.75)
const LABEL_W := 150.0

var _title: Label
var _sub: Label
var _templates: OptionButton
var _variant: SpinBox
var _rows: VBoxContainer
var _scroll: ScrollContainer
var _schema: Array = []
var _get: Callable                  # key -> current value
var _mode_key := ""
var _editors := {}                  # key -> callable(value) that updates its controls
var _template_ids: Array = []
var _presets: OptionButton
var _preset_name: LineEdit
var _rules_box: VBoxContainer
var _rules := {}                     # the rules being edited (Themes.RULE_DEFAULTS keys)
var _rule_opts := {}                 # rule key -> [[id, label], ...] (choices for list rules)


func _init() -> void:
	var st: NeonBox = UI.panel_style(Color(ACCENT, 0.7))
	st.bg_color = Color(st.bg_color, 0.97)   # opaque: the room's signs don't show through
	add_theme_stylebox_override("panel", st)
	custom_minimum_size = Vector2(440, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	_title = UI.label("", 20, ACCENT)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	head.add_child(_icon("duplicate", "Copy properties", "", "Copies every property of this asset to the clipboard (Godot's text\nformat: paste it into a template in the generator's script to keep it).", _copy))
	head.add_child(_icon("close", "Close the panel", "Esc", "Closes the property panel. Your edits stay on the exhibit until you\nleave the room or reset it.", func(): closed.emit()))
	_sub = UI.label("", 14, UI.TEXT_DIM)
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_sub)
	var tv := HBoxContainer.new()
	tv.add_theme_constant_override("separation", 8)
	v.add_child(tv)
	_templates = OptionButton.new()
	_templates.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_templates.tooltip_text = EditorIcons.tip("Template", "", "The template this asset starts from. Picking another regenerates it\nfrom that template (with the variant number on the right).")
	_templates.item_selected.connect(func(i): template_changed.emit(_template_ids[i]))
	tv.add_child(_templates)
	_variant = SpinBox.new()
	_variant.min_value = 0
	_variant.max_value = 99999
	_variant.custom_minimum_size = Vector2(110, 0)
	_variant.tooltip_text = EditorIcons.tip("Variant", "", "0 is the template itself; every other number mixes in features of the\nother templates and shifts the colours - each one different.")
	_variant.value_changed.connect(func(x): variant_changed.emit(int(x)))
	tv.add_child(_variant)
	tv.add_child(_icon("next", "Random variant", "", "Regenerates the asset as a random variant of its template.", func(): randomize_requested.emit()))
	tv.add_child(_icon("reload", "Reset", "", "Throws away your edits: back to the asset as it was in the room.", func(): reset_requested.emit()))
	# Editing tools.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	v.add_child(tools)
	tools.add_child(_icon("undo", "Undo", "Ctrl+Z", "Takes back the last property change (as many steps as you like).", func(): undo_requested.emit()))
	tools.add_child(_icon("redo", "Redo", "Ctrl+Y / Ctrl+Shift+Z", "Puts back a change you undid.", func(): redo_requested.emit()))
	tools.add_child(_icon("paste", "Paste properties", "Ctrl+V", "Pastes properties copied from another asset of the same kind\n(Copy at the top): colours, sliders and all.", func(): paste_requested.emit()))
	tools.add_child(_icon("apply", "Apply to all similar", "", "Gives every exhibit of this kind in the room this exact look\n(e.g. dress every character in this theme).", func(): apply_all_requested.emit()))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(sp)
	var rules_toggle := Button.new()
	rules_toggle.text = "Where and when..."
	rules_toggle.toggle_mode = true
	rules_toggle.focus_mode = Control.FOCUS_NONE
	rules_toggle.tooltip_text = EditorIcons.tip("Where and when it's used", "", "Shows the rules saved with a preset: which star systems, empires'\nsectors, planets, system conditions, story chapters and allegiances\nthe game uses this look in, how often, and its priority.")
	rules_toggle.toggled.connect(func(on): _rules_box.visible = on)
	tools.add_child(rules_toggle)
	# Named presets.
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 6)
	v.add_child(pr)
	_presets = OptionButton.new()
	_presets.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_presets.tooltip_text = EditorIcons.tip("Saved presets", "", "Your named looks for this kind of asset (data/themes.json).\nPick one to load it onto the selected exhibit, with its rules.")
	_presets.item_selected.connect(func(i):
		if i > 0:
			_preset_name.text = _presets.get_item_text(i)
			preset_load.emit(_presets.get_item_text(i)))
	pr.add_child(_presets)
	_preset_name = LineEdit.new()
	_preset_name.placeholder_text = "preset name"
	_preset_name.custom_minimum_size = Vector2(130, 0)
	_preset_name.tooltip_text = EditorIcons.tip("Preset name", "", "The name to save this look under. Saving with an existing name replaces it.")
	pr.add_child(_preset_name)
	pr.add_child(_icon("save", "Save preset", "Ctrl+S", "Saves the current look and its rules (Where and when...) as a named\npreset: the game then uses it wherever its rules match.", func():
		if _preset_name.text.strip_edges() != "":
			preset_save.emit(_preset_name.text.strip_edges(), _rules.duplicate(true))))
	pr.add_child(_icon("delete", "Delete preset", "", "Deletes the preset named in the box (the exhibit keeps its look).", func():
		if _preset_name.text.strip_edges() != "":
			preset_delete.emit(_preset_name.text.strip_edges())))
	_rules_box = VBoxContainer.new()
	_rules_box.visible = false
	v.add_child(_rules_box)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 4)
	_scroll.add_child(_rows)


func _icon(icon: String, title: String, keys: String, body: String, cb: Callable) -> Button:
	var b := UI.button("", cb, 16)
	EditorIcons.dress(b, icon, EditorIcons.tip(title, keys, body))
	b.focus_mode = Control.FOCUS_NONE
	return b


## Shows an asset: its title and description, the template list (ids and
## names, the current one), its variant, its schema and a getter for values.
## `mode_key`: the property whose value filters the rows by their modes.
func edit(title: String, sub: String, templates: Array, names: Array, template: String, variant: int,
		schema: Array, getter: Callable, mode_key := "") -> void:
	_title.text = title
	_sub.text = sub
	_template_ids = templates
	_templates.clear()
	for i in templates.size():
		_templates.add_item(names[i])
	_templates.select(maxi(templates.find(template), 0))
	_variant.set_value_no_signal(variant)
	_schema = schema
	_get = getter
	_mode_key = mode_key
	rebuild()


## The saved presets' names for the asset's kind.
func set_presets(names: Array, current := "") -> void:
	_presets.clear()
	_presets.add_item("- saved presets (%d) -" % names.size())
	for n in names:
		_presets.add_item(n)
	var i := names.find(current)
	_presets.select(i + 1 if i >= 0 else 0)


## Shows and edits a preset's rules. `options`: rule key -> [[id, label], ...]
## for the list rules (systems, owners, planets, states, templates, friends).
func set_rules(rules: Dictionary, options: Dictionary) -> void:
	_rules = Themes.RULE_DEFAULTS.duplicate(true)
	_rules.merge(rules, true)
	_rule_opts = options
	for c in _rules_box.get_children():
		c.queue_free()
	var head := UI.label("WHERE AND WHEN THE GAME USES THIS LOOK (saved with the preset)", 14, ACCENT)
	head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rules_box.add_child(head)
	var en := CheckBox.new()
	en.text = "Enabled"
	en.button_pressed = bool(_rules["enabled"])
	en.tooltip_text = EditorIcons.tip("Enabled", "", "Off: the preset is kept but the game never picks it.")
	en.toggled.connect(func(on): _rules["enabled"] = on)
	_rules_box.add_child(en)
	for k in [["systems", "Star systems"], ["owners", "Empires' sectors"], ["planets", "Planets"], ["states", "System conditions"],
			["templates", "Templates"], ["friends", "Empires that like you (Friendly+)"]]:
		if options.has(k[0]):
			_rules_box.add_child(_list_rule(k[0], k[1]))
	for k in [["chapter_min", "From chapter", "The first main-story stage it appears in (-1: from the start)."],
			["chapter_max", "Until chapter", "The last main-story stage it appears in (-1: forever)."],
			["priority", "Priority", "When several presets match, the highest priority wins (ties: shared out)."]]:
		var row := HBoxContainer.new()
		var l := UI.label(k[1], 14)
		l.custom_minimum_size = Vector2(LABEL_W, 0)
		row.add_child(l)
		var sb := SpinBox.new()
		sb.min_value = -1 if k[0] != "priority" else -100
		sb.max_value = 100
		sb.value = float(_rules[k[0]])
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.tooltip_text = EditorIcons.tip(k[1], "", k[2])
		var key: String = k[0]
		sb.value_changed.connect(func(x): _rules[key] = int(x))
		row.add_child(sb)
		_rules_box.add_child(row)
	var row := HBoxContainer.new()
	var cl := UI.label("Chance", 14)
	cl.custom_minimum_size = Vector2(LABEL_W, 0)
	row.add_child(cl)
	var s := _slider(0.0, 1.0, false, float(_rules["chance"]), EditorIcons.tip("Chance", "", "How often the game uses it where it matches (1: always; 0.3: three in ten)."))
	row.add_child(s[0])
	row.add_child(s[1])
	s[0].value_changed.connect(func(x): _rules["chance"] = x)
	_rules_box.add_child(row)


## A rule that is a list of allowed ids: a drop-down of check items.
func _list_rule(key: String, title: String) -> Control:
	var row := HBoxContainer.new()
	var l := UI.label(title, 14)
	l.custom_minimum_size = Vector2(LABEL_W, 0)
	row.add_child(l)
	var mb := MenuButton.new()
	mb.flat = false
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mb.tooltip_text = EditorIcons.tip(title, "", "Tick where it may appear. Nothing ticked: anywhere.")
	var pm := mb.get_popup()
	pm.hide_on_checkable_item_selection = false
	var opts: Array = _rule_opts[key]
	var sel: Array = _rules[key]
	for i in opts.size():
		pm.add_check_item(opts[i][1], i)
		pm.set_item_checked(i, sel.has(opts[i][0]))
	var refresh := func():
		var picked: Array = _rules[key]
		mb.text = "Any" if picked.is_empty() else ", ".join(opts.filter(func(o): return picked.has(o[0])).map(func(o): return o[1]))
	pm.id_pressed.connect(func(i):
		pm.set_item_checked(i, not pm.is_item_checked(i))
		var picked := []
		for j in opts.size():
			if pm.is_item_checked(j):
				picked.append(opts[j][0])
		_rules[key] = picked
		refresh.call())
	refresh.call()
	row.add_child(mb)
	return row


func preset_name() -> String:
	return _preset_name.text.strip_edges()


func notify(text: String) -> void:
	_sub.text = text


## Rebuilds the rows (after the mode changed: other properties apply).
func rebuild() -> void:
	var keep := _scroll.scroll_vertical
	for c in _rows.get_children():
		c.queue_free()
	_editors = {}
	var mode = _get.call(_mode_key) if _mode_key != "" else null
	var header: Control = null
	var in_group := 0
	for d in _schema:
		if d[0] == "#":
			if header and in_group == 0:
				header.queue_free()   # (a group with nothing that applies)
			header = UI.label(str(d[1]).to_upper(), 15, ACCENT)
			header.add_theme_constant_override("outline_size", 0)
			var m := MarginContainer.new()
			m.add_theme_constant_override("margin_top", 8)
			m.add_child(header)
			header = m
			_rows.add_child(m)
			in_group = 0
			continue
		var modes: Array = d[6] if d.size() > 6 else []
		if mode != null and not modes.is_empty() and not modes.has(int(mode)):
			continue
		_rows.add_child(_row(d))
		in_group += 1
	if header and in_group == 0:
		header.queue_free()
	await get_tree().process_frame
	_scroll.scroll_vertical = keep


## Number of property rows currently shown.
func row_count() -> int:
	return _editors.size()


## Sets a property's controls (without emitting).
func show_value(key: String, value: Variant) -> void:
	if _editors.has(key):
		_editors[key].call(value)


func _tip(d: Array) -> String:
	var t: String = d[2]
	var body: String = d[5]
	if t in ["float", "int", "vec2", "vec3"]:
		body += "\nRange: %s to %s." % [str(d[3]), str(d[4])]
	return EditorIcons.tip(d[1], "", body + "\nChanges show at once on the exhibit.")


func _row(d: Array) -> Control:
	var key: String = d[0]
	var type: String = d[2]
	var value = _get.call(key)
	if value == null:
		value = _fallback(d)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name_l := UI.label(d[1], 14)
	name_l.custom_minimum_size = Vector2(LABEL_W, 0)
	name_l.tooltip_text = _tip(d)
	name_l.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name_l)
	if type.begins_with("enum:"):
		var ob := OptionButton.new()
		for o in type.substr(5).split(","):
			ob.add_item(o)
		ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ob.select(int(value))
		ob.tooltip_text = _tip(d)
		ob.item_selected.connect(func(i): changed.emit(key, i))
		row.add_child(ob)
		_editors[key] = func(x): ob.select(int(x))
	elif type == "color":
		var cp := ColorPickerButton.new()
		cp.edit_alpha = false
		cp.color = value if value is Color else Color.WHITE
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cp.custom_minimum_size = Vector2(0, 26)
		cp.tooltip_text = _tip(d)
		cp.color_changed.connect(func(c): changed.emit(key, c))
		row.add_child(cp)
		_editors[key] = func(x): cp.color = x
	elif type == "vec2" or type == "vec3":
		var n := 2 if type == "vec2" else 3
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		var sliders := []
		var cur: Array = [value.x, value.y] if n == 2 else [value.x, value.y, value.z]
		for i in n:
			var sub := HBoxContainer.new()
			sub.add_child(UI.label("xyz"[i], 13, UI.TEXT_DIM))
			var s := _slider(float(d[3]), float(d[4]), false, cur[i], _tip(d))
			sub.add_child(s[0])
			sub.add_child(s[1])
			col.add_child(sub)
			sliders.append(s)
		var emit_vec := func():
			var vals := sliders.map(func(s): return float(s[0].value))
			changed.emit(key, Vector2(vals[0], vals[1]) if n == 2 else Vector3(vals[0], vals[1], vals[2]))
		for s in sliders:
			s[0].value_changed.connect(func(_x): emit_vec.call())
		_editors[key] = func(x):
			var arr: Array = [x.x, x.y] if n == 2 else [x.x, x.y, x.z]
			for i in n:
				sliders[i][0].set_value_no_signal(arr[i])
				sliders[i][1].set_value_no_signal(arr[i])
	else:
		var is_int := type == "int"
		var s := _slider(float(d[3]), float(d[4]), is_int, float(value), _tip(d))
		row.add_child(s[0])
		row.add_child(s[1])
		s[0].value_changed.connect(func(x): changed.emit(key, int(x) if is_int else x))
		_editors[key] = func(x):
			s[0].set_value_no_signal(float(x))
			s[1].set_value_no_signal(float(x))
	return row


## A value for a property nobody has set (and no shader default known).
func _fallback(d: Array) -> Variant:
	match str(d[2]):
		"color": return Color.WHITE
		"vec2": return Vector2(float(d[3]), float(d[3])).lerp(Vector2(float(d[4]), float(d[4])), 0.5)
		"vec3": return Vector3(0, 0, 1)
		"int": return int(d[3])
	if str(d[2]).begins_with("enum:"):
		return 0
	return clampf(0.0, float(d[3]), float(d[4]))


## A slider and a number box kept in step: [HSlider, SpinBox].
func _slider(lo: float, hi: float, is_int: bool, value: float, tip: String) -> Array:
	var step := 1.0 if is_int else maxf((hi - lo) / 400.0, 0.0001)
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.tooltip_text = tip
	sl.value = value
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.step = step
	sp.allow_greater = true
	sp.allow_lesser = true
	sp.custom_minimum_size = Vector2(84, 0)
	sp.tooltip_text = tip
	sp.value = value
	sl.value_changed.connect(func(x): sp.set_value_no_signal(x))
	sp.value_changed.connect(func(x): sl.value = x)
	return [sl, sp]


func _copy() -> void:
	var out := {}
	for d in _schema:
		if d[0] != "#":
			out[d[0]] = _get.call(d[0])
	DisplayServer.clipboard_set(var_to_str(out))
	_sub.text = "Copied %d properties to the clipboard." % out.size()
