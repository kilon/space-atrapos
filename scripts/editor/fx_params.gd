class_name FxParams
extends VBoxContainer
## An effect's parameters as widgets (Talos's Effects editor and the Live Editor's
## Particles tab): the effect's own (about, duration, its flash of light), then
## each emitter - every key of Fx.PARAMS as a slider, a min-max pair, a switch, a
## choice, a vector, a colour ramp (RampEdit) or a curve (CurveEdit) - with its
## name, on / off, duplicate, move up / down and delete. Each change goes straight
## into the definition (Fx.set_def: every live effect of it rebuilt at once).
##   var p := FxParams.new(); p.compact = true; add_child(p); p.show_effect("explosion")
##   p.before_edit -> the host's undo step (key: what's about to change); p.changed -> after.

signal before_edit(key: String)
signal changed()

const LABEL_W := 118
const FS := 13

## Narrow (the Live Editor's dock): fewer, smaller widgets a row.
var compact := false
var effect := ""
var _open := {}                 # emitter index -> its parameters shown
var _body: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	size_flags_horizontal = SIZE_EXPAND_FILL


func show_effect(name: String) -> void:
	effect = name
	rebuild()


func rebuild() -> void:
	UI.clear(self)
	if effect == "" or not Fx.has(effect):
		add_child(UI.label("No effect chosen.", 14, UI.TEXT_DIM))
		return
	var d := Fx.def(effect)
	add_child(UI.section("EFFECT"))
	var g := _grid()
	add_child(g)
	_text_row(g, "about", str(d.get("about", "")), Fx.EFFECT_PARAMS[0], func(v): _set_effect("about", v))
	_float_row(g, Fx.EFFECT_PARAMS[1], float(d.get("duration", 1.0)), func(v): _set_effect("duration", v))
	var l: Dictionary = d.get("light", {}) if d.get("light") is Dictionary else {}
	for p in Fx.LIGHT_PARAMS:
		var cur = l.get(p[0], p[2])
		if p[1] == "color":
			_color_row(g, p, Fx.color_of(cur), func(c: Color): _set_light(p[0], "#" + c.to_html(true)))
		else:
			_float_row(g, p, float(cur), func(v): _set_light(p[0], v))
	var ems: Array = d.get("emitters", [])
	for i in ems.size():
		_emitter(i, ems[i] if ems[i] is Dictionary else {})
	var add := _btn("Add emitter", "add", "A new emitter in this effect (a soft glow, to start from).", func(): add_emitter())
	add.name = "AddEmitter"
	add_child(add)


# --- Edits ---------------------------------------------------------------------------

## Emitter `i`'s `key` as the definition has it now.
func _cur(i: int, key: String) -> Variant:
	var ems: Array = Fx.def(effect).get("emitters", [])
	return Fx.val(ems[i], key) if i < ems.size() and ems[i] is Dictionary else null


func _def() -> Dictionary:
	return Fx.def(effect).duplicate(true)


func _commit(d: Dictionary) -> void:
	Fx.set_def(effect, d)
	changed.emit()


func _set_effect(key: String, v: Variant) -> void:
	before_edit.emit(key)
	var d := _def()
	d[key] = v
	_commit(d)


func _set_light(key: String, v: Variant) -> void:
	before_edit.emit("light." + key)
	var d := _def()
	var l: Dictionary = d.get("light", {}) if d.get("light") is Dictionary else {}
	l[key] = v
	d["light"] = l
	_commit(d)


## Emitter `i`'s `key` set to `v` (the definition changed, every live effect rebuilt).
func set_value(i: int, key: String, v: Variant) -> void:
	var d := _def()
	var ems: Array = d.get("emitters", [])
	if i < 0 or i >= ems.size():
		return
	before_edit.emit("%d.%s" % [i, key])
	(ems[i] as Dictionary)[key] = v
	_commit(d)


func add_emitter(from: Dictionary = {}) -> void:
	before_edit.emit("+emitter")
	var d := _def()
	var ems: Array = d.get("emitters", [])
	var e := from.duplicate(true) if not from.is_empty() else Fx.new_emitter()
	if from.is_empty():
		e["name"] = "glow %d" % (ems.size() + 1)
		e["velocity"] = [0.0, 0.0]
		e["scale"] = [2.0, 2.0]
		e["amount"] = 1
		e["lifetime"] = 0.5
	ems.append(e)
	d["emitters"] = ems
	_open[ems.size() - 1] = true
	_commit(d)
	rebuild()


func _remove(i: int) -> void:
	before_edit.emit("-emitter")
	var d := _def()
	(d["emitters"] as Array).remove_at(i)
	_open.clear()
	_commit(d)
	rebuild()


func _move(i: int, by: int) -> void:
	var d := _def()
	var ems: Array = d["emitters"]
	var j := i + by
	if j < 0 or j >= ems.size():
		return
	before_edit.emit("~emitter")
	var e = ems[i]
	ems[i] = ems[j]
	ems[j] = e
	var oi = _open.get(i, false)
	_open[i] = _open.get(j, false)
	_open[j] = oi
	_commit(d)
	rebuild()


# --- Widgets ---------------------------------------------------------------------------

func _emitter(i: int, e: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	var fold := Button.new()
	fold.toggle_mode = true
	fold.focus_mode = FOCUS_NONE
	fold.button_pressed = bool(_open.get(i, false))
	fold.text = "v" if fold.button_pressed else ">"
	fold.custom_minimum_size.x = 28
	fold.add_theme_font_size_override("font_size", FS)
	fold.tooltip_text = EditorIcons.tip("Show its parameters", "", "Opens (or folds) this emitter's parameters.")
	fold.name = "Fold%d" % i
	head.add_child(fold)
	var on := CheckBox.new()
	on.focus_mode = FOCUS_NONE
	on.button_pressed = bool(Fx.val(e, "on"))
	on.tooltip_text = EditorIcons.tip("On", "", Fx.param("on")[6])
	on.toggled.connect(func(v): set_value(i, "on", v))
	head.add_child(on)
	var nm := LineEdit.new()
	nm.text = str(Fx.val(e, "name"))
	nm.size_flags_horizontal = SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", 14)
	nm.tooltip_text = EditorIcons.tip("Emitter name", "Enter", Fx.param("name")[6])
	nm.text_submitted.connect(func(t): set_value(i, "name", t); nm.release_focus())
	nm.focus_exited.connect(func(): if nm.text != str(_cur(i, "name")): set_value(i, "name", nm.text))
	head.add_child(nm)
	var mat := UI.label("(%s)" % str(Fx.val(e, "material")), FS, UI.TEXT_DIM)
	head.add_child(mat)
	add_child(head)
	var body := VBoxContainer.new()
	body.name = "Emitter%d" % i
	body.visible = fold.button_pressed
	add_child(body)
	fold.toggled.connect(func(v):
		_open[i] = v
		fold.text = "v" if v else ">"
		body.visible = v
		if v and body.get_child_count() == 0:
			_emitter_body(body, i, e))
	if body.visible:
		_emitter_body(body, i, e)


func _emitter_body(body: VBoxContainer, i: int, e: Dictionary) -> void:
	var acts := HBoxContainer.new()
	acts.add_child(_btn("Duplicate emitter", "duplicate", "A copy of this emitter, after it.", func(): add_emitter(Fx.def(effect)["emitters"][i]), "Copy"))
	acts.add_child(_btn("Move up", "up", "Earlier in the list (drawn under the ones after it).", func(): _move(i, -1), "Up"))
	acts.add_child(_btn("Move down", "down", "Later in the list (drawn over the ones before it).", func(): _move(i, 1), "Down"))
	acts.add_child(_btn("Delete emitter", "delete", "Takes this emitter out of the effect (Undo puts it back).", func(): _remove(i), "Delete"))
	body.add_child(acts)
	var g := _grid()
	body.add_child(g)
	for p in Fx.PARAMS:
		var key: String = p[0]
		if key in ["name", "on"]:
			continue
		var cur = Fx.val(e, key)
		match str(p[1]):
			"enum":
				_enum_row(g, p, str(cur), func(v): set_value(i, key, v); rebuild())
			"bool":
				_bool_row(g, p, bool(cur), func(v): set_value(i, key, v))
			"int":
				_float_row(g, p, float(cur), func(v): set_value(i, key, int(v)), true)
			"float":
				_float_row(g, p, float(cur), func(v): set_value(i, key, v))
			"range":
				_range_row(g, p, Fx._rng2(cur), func(v: Vector2): set_value(i, key, [v.x, v.y]))
			"vec3":
				_vec3_row(g, p, Fx._vec3(cur), func(v: Vector3): set_value(i, key, [v.x, v.y, v.z]))
			"colors":
				var r := RampEdit.new()
				r.stops = (cur as Array).duplicate(true) if cur is Array else []
				r.name = "Ramp_%d" % i
				r.edited.connect(func(stops): set_value(i, key, stops))
				_row(g, p, r)
			"curve":
				var c := CurveEdit.new()
				c.points = (cur as Array).duplicate(true) if cur is Array else []
				c.name = "Curve_%d" % i
				c.edited.connect(func(pts): set_value(i, key, pts))
				_row(g, p, c)


func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 4)
	g.size_flags_horizontal = SIZE_EXPAND_FILL
	return g


func _row(g: GridContainer, p: Array, w: Control) -> void:
	var l := UI.label(str(p[5]), FS, UI.TEXT_DIM)
	l.custom_minimum_size.x = LABEL_W - (16 if compact else 0)
	var t := tip_of(p)
	l.tooltip_text = t
	l.mouse_filter = MOUSE_FILTER_STOP
	l.clip_text = true
	g.add_child(l)
	w.size_flags_horizontal = SIZE_EXPAND_FILL
	if w.tooltip_text == "":
		w.tooltip_text = t
	for c in w.find_children("*", "Control", true, false):   # (the slider and the box in a number's row)
		if (c is Range or c is BaseButton or c is LineEdit) and (c as Control).tooltip_text == "":
			(c as Control).tooltip_text = t
	g.add_child(w)


## A parameter's tooltip ([key, kind, default, least, most, label, what it is]):
## what it is, then its range and default.
static func tip_of(p: Array, which := "") -> String:
	var more := ""
	if (p[3] is float or p[3] is int) and (p[4] is float or p[4] is int):
		more = "\nFrom %s to %s; default %s." % [str(p[3]), str(p[4]), str(p[2])]
	return EditorIcons.tip(str(p[5]) + which, "", str(p[6]) + more)


func _spin(lo: float, hi: float, v: float, whole := false) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1.0 if whole else 0.01   # (snapped from its least value: a coarser step turned 1.0 into 1.05)
	s.allow_greater = true
	s.allow_lesser = lo < 0.0
	s.value = v
	s.custom_minimum_size.x = 64 if compact else 78
	s.select_all_on_focus = true
	s.get_line_edit().add_theme_font_size_override("font_size", FS)
	return s


func _float_row(g: GridContainer, p: Array, v: float, set_v: Callable, whole := false) -> void:
	var lo := float(p[3])
	var hi := float(p[4])
	var row := HBoxContainer.new()
	var sl := HSlider.new()
	sl.min_value = lo
	sl.max_value = hi
	sl.step = 1.0 if whole else 0.001
	sl.value = v
	sl.size_flags_horizontal = SIZE_EXPAND_FILL
	sl.size_flags_vertical = SIZE_SHRINK_CENTER
	sl.focus_mode = FOCUS_NONE
	var sp := _spin(lo, hi, v, whole)
	sl.value_changed.connect(func(x):
		sp.set_value_no_signal(x)
		set_v.call(snappedf(x, 0.001)))
	sp.value_changed.connect(func(x):
		sl.set_value_no_signal(x)
		set_v.call(snappedf(x, 0.001)))
	row.add_child(sl)
	row.add_child(sp)
	row.name = "P_" + str(p[0])
	_row(g, p, row)


func _range_row(g: GridContainer, p: Array, v: Vector2, set_v: Callable) -> void:
	var row := HBoxContainer.new()
	row.name = "P_" + str(p[0])
	var a := _spin(float(p[3]), float(p[4]), v.x)
	var b := _spin(float(p[3]), float(p[4]), v.y)
	a.size_flags_horizontal = SIZE_EXPAND_FILL
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	a.tooltip_text = tip_of(p, " (least)")
	b.tooltip_text = tip_of(p, " (most)")
	var go := func(_x): set_v.call(Vector2(snappedf(a.value, 0.001), snappedf(b.value, 0.001)))
	a.value_changed.connect(go)
	b.value_changed.connect(go)
	row.add_child(a)
	row.add_child(UI.label("-", FS, UI.TEXT_DIM))
	row.add_child(b)
	_row(g, p, row)


func _vec3_row(g: GridContainer, p: Array, v: Vector3, set_v: Callable) -> void:
	var row := HBoxContainer.new()
	row.name = "P_" + str(p[0])
	var s: Array = []
	for k in 3:
		var sp := _spin(float(p[3]), float(p[4]), v[k])
		sp.size_flags_horizontal = SIZE_EXPAND_FILL
		sp.custom_minimum_size.x = 56
		sp.prefix = ["x", "y", "z"][k]
		s.append(sp)
		row.add_child(sp)
	var go := func(_x): set_v.call(Vector3(snappedf(s[0].value, 0.001), snappedf(s[1].value, 0.001), snappedf(s[2].value, 0.001)))
	for sp in s:
		sp.value_changed.connect(go)
	_row(g, p, row)


func _bool_row(g: GridContainer, p: Array, v: bool, set_v: Callable) -> void:
	var c := CheckBox.new()
	c.focus_mode = FOCUS_NONE
	c.button_pressed = v
	c.name = "P_" + str(p[0])
	c.toggled.connect(func(x): set_v.call(x))
	_row(g, p, c)


func _enum_row(g: GridContainer, p: Array, v: String, set_v: Callable) -> void:
	var o := OptionButton.new()
	o.focus_mode = FOCUS_NONE
	o.name = "P_" + str(p[0])
	o.add_theme_font_size_override("font_size", FS)
	for x in p[3]:
		o.add_item(str(x))
	o.select(maxi(0, (p[3] as Array).find(v)))
	o.item_selected.connect(func(k): set_v.call(str(p[3][k])))
	_row(g, p, o)


func _color_row(g: GridContainer, p: Array, v: Color, set_v: Callable) -> void:
	var c := ColorPickerButton.new()
	c.color = v
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(60, 24)
	c.focus_mode = FOCUS_NONE
	c.color_changed.connect(func(x): set_v.call(x))
	_row(g, p, c)


func _text_row(g: GridContainer, _key: String, v: String, p: Array, set_v: Callable) -> void:
	var t := LineEdit.new()
	t.text = v
	t.add_theme_font_size_override("font_size", FS)
	t.text_submitted.connect(func(x): set_v.call(x); t.release_focus())
	t.focus_exited.connect(func(): if t.text != str(Fx.def(effect).get(p[0], "")): set_v.call(t.text))
	_row(g, p, t)


func _btn(name: String, icon: String, help: String, cb: Callable, label := "") -> Button:
	var b := UI.button("", cb, 14)
	b.focus_mode = FOCUS_NONE
	return EditorIcons.dress(b, icon, EditorIcons.tip(name, "", help), label)


# --- The colour ramp -------------------------------------------------------------------

## A colour ramp: the colours along a particle's life (a bar, checked under to show
## the opacity), a handle under each stop. Click a handle to pick it (its colour in
## the picker beside), drag it along; double-click the bar for a new stop there;
## right-click a handle to take it away (two at least).
class RampEdit extends VBoxContainer:
	signal edited(stops: Array)
	var stops: Array = []
	var sel := 0
	var _bar: Bar
	var _pick: ColorPickerButton

	func _ready() -> void:
		var row := HBoxContainer.new()
		_bar = Bar.new()
		_bar.ed = self
		_bar.custom_minimum_size = Vector2(120, 34)
		_bar.size_flags_horizontal = SIZE_EXPAND_FILL
		_bar.mouse_filter = MOUSE_FILTER_STOP
		_bar.tooltip_text = EditorIcons.tip("Colour over life", "", "Click a handle to pick it, drag it along; double-click for a new stop; right-click a handle to remove it.")
		row.add_child(_bar)
		_pick = ColorPickerButton.new()
		_pick.edit_alpha = true
		_pick.custom_minimum_size = Vector2(44, 30)
		_pick.focus_mode = FOCUS_NONE
		_pick.tooltip_text = EditorIcons.tip("Stop colour", "", "The picked stop's colour and opacity.")
		_pick.color_changed.connect(func(c):
			if sel < stops.size():
				stops[sel][1] = "#" + c.to_html(true)
				_bar.queue_redraw()
				edited.emit(stops.duplicate(true)))
		row.add_child(_pick)
		add_child(row)
		_sync()

	func _sync() -> void:
		sel = clampi(sel, 0, maxi(0, stops.size() - 1))
		if _pick and sel < stops.size():
			_pick.color = Fx.color_of(stops[sel][1])
		if _bar:
			_bar.queue_redraw()

	func pick(i: int) -> void:
		sel = i
		_sync()

	func add_at(t: float) -> void:
		var g := Fx.gradient(stops)
		stops.append([snappedf(t, 0.001), "#" + g.sample(t).to_html(true)])
		stops.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		for i in stops.size():
			if absf(float(stops[i][0]) - snappedf(t, 0.001)) < 0.0005:
				sel = i
		_sync()
		edited.emit(stops.duplicate(true))

	func remove(i: int) -> void:
		if stops.size() <= 2:
			return
		stops.remove_at(i)
		_sync()
		edited.emit(stops.duplicate(true))

	func move(i: int, t: float) -> void:
		stops[i][0] = snappedf(clampf(t, 0.0, 1.0), 0.001)
		_bar.queue_redraw()
		edited.emit(stops.duplicate(true))

	class Bar extends Control:
		var ed
		var _drag := -1

		func _x(t: float) -> float:
			return 6.0 + t * (size.x - 12.0)

		func _t(x: float) -> float:
			return clampf((x - 6.0) / maxf(size.x - 12.0, 1.0), 0.0, 1.0)

		func _draw() -> void:
			var h := size.y - 12.0
			var w := size.x - 12.0
			var n := 12
			for k in n:   # (the checks under: opacity shows)
				for r in 2:
					draw_rect(Rect2(6.0 + w * k / n, r * h * 0.5, w / n, h * 0.5), Color(0.32, 0.32, 0.34) if (k + r) % 2 == 0 else Color(0.18, 0.18, 0.2))
			var g := Fx.gradient(ed.stops)
			var steps := 64
			for k in steps:
				var c := g.sample((k + 0.5) / steps)
				draw_rect(Rect2(6.0 + w * k / steps, 0, w / steps + 1.0, h), c)
			draw_rect(Rect2(6, 0, w, h), Color(1, 1, 1, 0.35), false, 1.0)
			for i in ed.stops.size():
				var x := _x(float(ed.stops[i][0]))
				var col := Fx.color_of(ed.stops[i][1])
				var pts := PackedVector2Array([Vector2(x, h), Vector2(x - 6, h + 11), Vector2(x + 6, h + 11)])
				draw_colored_polygon(pts, Color(col, 1.0))
				pts.append(pts[0])
				draw_polyline(pts, Color(1, 0.85, 0.4) if i == ed.sel else Color(0.9, 0.9, 0.9, 0.8), 2.0 if i == ed.sel else 1.0)

		func _hit(x: float) -> int:
			var best := -1
			var bd := 9.0
			for i in ed.stops.size():
				var d := absf(_x(float(ed.stops[i][0])) - x)
				if d < bd:
					bd = d
					best = i
			return best

		func _gui_input(event: InputEvent) -> void:
			var mb := event as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				if mb.double_click:
					ed.add_at(_t(mb.position.x))
				else:
					var i := _hit(mb.position.x)
					if i >= 0:
						ed.pick(i)
						_drag = i
				accept_event()
			elif mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				_drag = -1
			elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
				var i := _hit(mb.position.x)
				if i >= 0:
					ed.remove(i)
				accept_event()
			var mm := event as InputEventMouseMotion
			if mm and _drag >= 0 and _drag < ed.stops.size():
				ed.move(_drag, _t(mm.position.x))


# --- The scale curve -------------------------------------------------------------------

## A curve over a particle's life (x: age 0-1, y: times its scale). Drag a point;
## double-click for a new one; right-click one to take it away. Empty: the same
## size all its life (double-click to start one).
class CurveEdit extends Control:
	signal edited(points: Array)
	var points: Array = []
	var _drag := -1

	func _init() -> void:
		custom_minimum_size = Vector2(120, 84)
		mouse_filter = MOUSE_FILTER_STOP
		tooltip_text = EditorIcons.tip("Scale over life", "", "Drag a point (x: age, y: times the scale); double-click for a new one,\nright-click one to remove it. Empty: the same size all its life.")

	func _top() -> float:
		var hi := 2.0
		for p in points:
			hi = maxf(hi, float(p[1]) * 1.15)
		return hi

	func _pos(p: Array) -> Vector2:
		return Vector2(6.0 + float(p[0]) * (size.x - 12.0), size.y - 6.0 - float(p[1]) / _top() * (size.y - 12.0))

	func _val(at: Vector2) -> Array:
		return [snappedf(clampf((at.x - 6.0) / maxf(size.x - 12.0, 1.0), 0.0, 1.0), 0.001),
			snappedf(clampf((size.y - 6.0 - at.y) / maxf(size.y - 12.0, 1.0), 0.0, 1.0) * _top(), 0.001)]

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07, 0.8))
		var one := _pos([0.0, 1.0]).y
		draw_line(Vector2(6, one), Vector2(size.x - 6, one), Color(1, 1, 1, 0.18), 1.0)
		for k in 5:
			var x := 6.0 + (size.x - 12.0) * k / 4.0
			draw_line(Vector2(x, 6), Vector2(x, size.y - 6), Color(1, 1, 1, 0.07), 1.0)
		if points.size() < 2:
			draw_line(Vector2(6, one), Vector2(size.x - 6, one), Color(1, 0.75, 0.4, 0.7), 2.0)
			draw_string(get_theme_default_font(), Vector2(10, size.y - 10), "none - double-click to start", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.5))
			return
		var s := points.duplicate()
		s.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		var line := PackedVector2Array()
		line.append(Vector2(6, _pos(s[0]).y))
		for p in s:
			line.append(_pos(p))
		line.append(Vector2(size.x - 6, _pos(s[-1]).y))
		draw_polyline(line, Color(1, 0.75, 0.4), 2.0)
		for i in points.size():
			draw_circle(_pos(points[i]), 5.0 if i == _drag else 4.0, Color(1, 0.9, 0.6))

	func _hit(at: Vector2) -> int:
		for i in points.size():
			if _pos(points[i]).distance_to(at) < 9.0:
				return i
		return -1

	func _emit() -> void:
		var s := points.duplicate(true)
		s.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
		edited.emit(s)

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.double_click:
				if points.size() < 2:
					points = [[0.0, 1.0], [1.0, 1.0]]
				else:
					points.append(_val(mb.position))
				_emit()
			else:
				_drag = _hit(mb.position)
			queue_redraw()
			accept_event()
		elif mb and not mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = -1
			queue_redraw()
		elif mb and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			var i := _hit(mb.position)
			if i >= 0:
				points.remove_at(i)
				if points.size() < 2:
					points = []
				_emit()
				queue_redraw()
			accept_event()
		var mm := event as InputEventMouseMotion
		if mm and _drag >= 0 and _drag < points.size():
			points[_drag] = _val(mm.position)
			_emit()
			queue_redraw()
