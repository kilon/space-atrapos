extends VBoxContainer
## The Live Editor's Object tab: what's picked - where it is, its turn and size,
## shown or not, its shadow - and its values (its script's variables: speeds,
## sizes, colours, names...), each edited live. Kept (LiveEdits, section "object"):
## {rel path: {property: value}} - put back on every thing of that kind.

const TITLE := "Object"
const ICON := "select"
const REFRESH := 0.25
## The values not shown (the engine's own bookkeeping).
const SKIP := ["script", "owner", "name", "scene_file_path", "process_mode", "process_priority"]
## The place rows' tooltips.
const ABOUT := {"position": "Where it is (metres), from what it's part of.", "rotation_degrees": "Its turn (degrees) about x (pitch), y (yaw), z (roll).",
	"scale": "Its size: 1 as made (x, y, z each).", "visible": "Shown or hidden.",
	"cast_shadow": "Its shadow: 0 none, 1 on, 2 both sides, 3 the shadow only (itself unseen).", "transparency": "See-through: 0 solid, 1 invisible."}

var ed: Node
var _rows := {}         # property -> [widget row, getter]
var _t := 0.0
var _rel := "."


static func handles(n: Node) -> bool:
	return n is Node3D


func bind(e: Node) -> void:
	ed = e
	var n: Node = ed.selected
	if ed.anchor:
		_rel = LiveEdits.rel_path(ed.anchor, n)
	add_child(LiveFields.head("PLACE"))
	if n is Node3D:
		# (the whole thing's own place and turn are where this one is - live, not kept for its kind)
		_prop(n, "position", "Position (m)", "", false, _rel != ".")
		_prop(n, "rotation_degrees", "Turn (degrees)", "", false, _rel != ".")
		_prop(n, "scale", "Size")
		_prop(n, "visible", "Shown")
	if n is GeometryInstance3D:
		_prop(n, "cast_shadow", "Shadow (0 off, 1 on)", "0,3,1")
		_prop(n, "transparency", "See-through", "0,1,0.01")
	var vals := _script_values(ed.anchor if ed.anchor else n)
	if not vals.is_empty():
		add_child(LiveFields.head("ITS VALUES  (%s)" % str(ed.anchor.name if ed.anchor else n.name)))
		var target: Node = ed.anchor if ed.anchor else n
		for p in vals:
			_prop(target, p["name"], p["name"].capitalize(), p.get("hint_string", "") if int(p.get("hint", 0)) == PROPERTY_HINT_RANGE else "", true)
	var forget := UI.button("Forget its edits", func():
		LiveEdits.forget(ed.key, "object")
		ed.say("Its kept edits forgotten - as made, the next time it's made."), 14)
	forget.tooltip_text = "Drops the edits kept for this kind of thing (what you see now stays till it's made again)."
	add_child(forget)


func unbind() -> void:
	ed = null


## A property `p` of `obj` as a row; `anchor_prop`: kept against the anchor itself.
func _prop(obj: Object, p: String, label: String, hint := "", anchor_prop := false, keep := true) -> void:
	var v = obj.get(p)
	if v == null:
		return
	var rel := "." if anchor_prop else _rel
	var about: String = ABOUT.get(p, "") if not anchor_prop else "Its script's value \"%s\" (%s): what it's made with or what it's at now." % [p, str(obj.get_script().resource_path.get_file()) if obj.get_script() else obj.get_class()]
	if keep:
		about += "\nKept for every thing of this kind (Save)." if ed and ed.key != "" else "\nLasts till it's gone (not part of anything kept)."
	else:
		about += "\nLive only: not kept."
	var row := LiveFields.row(label, v, func(nv):
		if not is_instance_valid(obj):
			return
		obj.set(p, nv)
		if ed and ed.key != "" and keep:
			var sec := LiveEdits.section(ed.key, "object")
			if not sec.has(rel):
				sec[rel] = {}
			sec[rel][p] = LiveEdits.enc(nv)
			ed.edited("object"), hint, about)
	add_child(row)
	_rows[p] = [row, obj]


## Its script's own variables of simple types (what it's made with and what it's at).
func _script_values(n: Node) -> Array:
	var out := []
	if n == null or n.get_script() == null:
		return out
	for p in n.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		if str(p["name"]).begins_with("_") or p["name"] in SKIP:
			continue
		if not int(p["type"]) in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR3, TYPE_COLOR]:
			continue
		out.append(p)
		if out.size() >= 40:
			break
	return out


## Live values: refreshed a few times a second (not the one being typed in).
func live_process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH
	var focus := get_viewport().gui_get_focus_owner()
	for p in _rows:
		var row: Control = _rows[p][0]
		var obj: Object = _rows[p][1]
		if not is_instance_valid(obj):
			continue
		var w: Control = row.get_meta("widget")
		if focus and (w == focus or w.is_ancestor_of(focus)):
			continue
		_show(w, obj.get(p))


func _show(w: Control, v: Variant) -> void:
	if w is CheckBox:
		(w as CheckBox).set_pressed_no_signal(bool(v))
	elif w is SpinBox:
		(w as SpinBox).set_value_no_signal(float(v))
	elif w is LineEdit:
		(w as LineEdit).text = str(v)
	elif w is ColorPickerButton:
		(w as ColorPickerButton).color = v
	elif w is HBoxContainer:
		var k := 0
		for c in w.get_children():
			if c is SpinBox and k < 4:
				(c as SpinBox).set_value_no_signal(float(v[k]))
				k += 1
			elif c is HSlider:
				(c as HSlider).set_value_no_signal(float(v))


## Puts the kept values back on a thing of that kind.
static func apply_edit(anchor: Node, data: Dictionary) -> void:
	for rel in data:
		var n := LiveEdits.find(anchor, str(rel))
		if n == null:
			continue
		for p in data[rel]:
			n.set(p, LiveEdits.dec(data[rel][p]))
