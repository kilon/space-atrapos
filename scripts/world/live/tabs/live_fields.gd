class_name LiveFields
extends RefCounted
## The Live Editor tabs' fields: a value of any simple type as a labelled widget
## (a tick, a number, a slider in a range, text, a vector, a colour), calling back
## with the new value as it's edited.


## A row: `label` and a widget for `value`; `on_change(v)` as it's edited. `hint`:
## "min,max[,step]" for a slider. Null - an unknown type (shown, not editable).
## `about`: what the value is (the tooltip's text; the value's kind and range are
## added to it - made from the value alone when it's "").
static func row(label: String, value: Variant, on_change: Callable, hint := "", about := "") -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := UI.label(label, 14, UI.TEXT_DIM)
	l.custom_minimum_size.x = 130
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var t := tip_for(label, value, hint, about)
	l.tooltip_text = t
	h.add_child(l)
	var w := widget(value, on_change, hint)
	w.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(w)
	give_tip(w, t)
	h.set_meta("widget", w)
	return h


## A field's tooltip: its name, what it is (`about`), then the kind of value and
## its range ("min,max[,step]" `hint`) and how to change it.
static func tip_for(label: String, value: Variant, hint := "", about := "") -> String:
	var how := ""
	match typeof(value):
		TYPE_BOOL:
			how = "On or off: tick it to turn it on."
		TYPE_INT, TYPE_FLOAT:
			var whole := typeof(value) == TYPE_INT
			var r := hint.split(",")
			if r.size() >= 2 and r[0].is_valid_float() and r[1].is_valid_float():
				how = "%s from %s to %s%s: drag the slider." % ["A whole number" if whole else "A number", _num(float(r[0]), whole), _num(float(r[1]), whole),
					(", in steps of " + r[2]) if r.size() > 2 and r[2].is_valid_float() and not whole else ""]
			else:
				how = "%s: type it (Enter), or use the arrows / the mouse wheel over it." % ("A whole number" if whole else "A number")
		TYPE_STRING, TYPE_STRING_NAME:
			how = "Text: type it, then Enter (or click away)."
		TYPE_VECTOR2, TYPE_VECTOR2I:
			how = "Two numbers, x and y: one box each."
		TYPE_VECTOR3, TYPE_VECTOR3I:
			how = "Three numbers, x, y and z (z: forward / back): one box each."
		TYPE_VECTOR4:
			how = "Four numbers, x, y, z and w: one box each."
		TYPE_COLOR:
			how = "A colour: click to pick it (with its opacity, alpha)."
		_:
			how = "Shown, not editable here."
	return EditorIcons.tip(label, "", (about + "\n" if about != "" else "") + how)


## Puts tooltip `t` on `w` and on every control in it you can use.
static func give_tip(w: Control, t: String) -> void:
	if w.tooltip_text == "":
		w.tooltip_text = t
	for c in w.find_children("*", "Control", true, false):
		if (c is BaseButton or c is Range or c is LineEdit) and (c as Control).tooltip_text == "":
			(c as Control).tooltip_text = t


static func widget(value: Variant, on_change: Callable, hint := "") -> Control:
	match typeof(value):
		TYPE_BOOL:
			var c := CheckBox.new()
			c.button_pressed = value
			c.focus_mode = Control.FOCUS_NONE
			c.toggled.connect(func(v): on_change.call(v))
			return c
		TYPE_INT, TYPE_FLOAT:
			var r := hint.split(",")
			if r.size() >= 2 and r[0].is_valid_float() and r[1].is_valid_float():
				return _slider(float(value), float(r[0]), float(r[1]), float(r[2]) if r.size() > 2 and r[2].is_valid_float() else (1.0 if typeof(value) == TYPE_INT else 0.001), typeof(value) == TYPE_INT, on_change)
			var s := _spin(float(value), typeof(value) == TYPE_INT)
			s.value_changed.connect(func(v): on_change.call(int(v) if typeof(value) == TYPE_INT else v))
			return s
		TYPE_STRING, TYPE_STRING_NAME:
			var e := LineEdit.new()
			e.text = str(value)
			e.text_submitted.connect(func(t): on_change.call(t))
			e.focus_exited.connect(func(): on_change.call(e.text))
			return e
		TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_VECTOR2I, TYPE_VECTOR3I:
			return _vector(value, on_change)
		TYPE_COLOR:
			var cp := ColorPickerButton.new()
			cp.color = value
			cp.custom_minimum_size = Vector2(80, 28)
			cp.focus_mode = Control.FOCUS_NONE
			cp.color_changed.connect(func(c): on_change.call(c))
			return cp
	var lab := UI.label(_brief(value), 14, UI.TEXT_DIM)
	lab.clip_text = true
	return lab


static func _spin(v: float, whole: bool) -> SpinBox:
	var s := SpinBox.new()
	s.allow_greater = true
	s.allow_lesser = true
	s.min_value = -1e6
	s.max_value = 1e6
	s.step = 1.0 if whole else 0.001
	s.value = v
	s.custom_minimum_size.x = 64
	s.update_on_text_changed = false
	s.get_line_edit().expand_to_text_length = false
	return s


static func _slider(v: float, lo: float, hi: float, step: float, whole: bool, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = step
	sl.value = v
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.focus_mode = Control.FOCUS_NONE
	h.add_child(sl)
	var n := UI.label(_num(v, whole), 14)
	n.custom_minimum_size.x = 48
	h.add_child(n)
	sl.value_changed.connect(func(x):
		n.text = _num(x, whole)
		on_change.call(int(x) if whole else x))
	return h


static func _num(v: float, whole: bool) -> String:
	return str(int(v)) if whole else ("%.3f" % v).rstrip("0").rstrip(".")


static func _vector(value: Variant, on_change: Callable) -> Control:
	var h := HBoxContainer.new()
	var n := 2 if (value is Vector2 or value is Vector2i) else (3 if (value is Vector3 or value is Vector3i) else 4)
	var whole := value is Vector2i or value is Vector3i
	var cur := [value]
	for i in n:
		var s := _spin(float(value[i]), whole)
		s.custom_minimum_size.x = 0
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.value_changed.connect(func(x):
			var v = cur[0]
			v[i] = int(x) if whole else x
			cur[0] = v
			on_change.call(v))
		h.add_child(s)
	return h


static func _brief(v: Variant) -> String:
	if v is Object:
		return (v as Object).get_class() if v else "(none)"
	var s := str(v)
	return s if s.length() < 60 else s.left(57) + "..."


## A heading inside a tab.
static func head(text: String) -> Label:
	return UI.section(text)
