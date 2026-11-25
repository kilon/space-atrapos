extends VBoxContainer
## The Live Editor's Particles tab: the particle effects (Fx - data/effects.json) on
## what's picked - the ones playing under it, its kind's (its anchor's), or any
## effect of the game - their parameters edited live (FxParams): an edit changes
## the effect's definition, so every effect of that name in the game (every
## explosion, every landing's dust) changes at once. Add an effect to the picked
## thing (attached at its origin): kept by LiveEdits (section "fx": {added: [{path,
## effect, pos}]}) and put back each time that kind of thing is made (apply_edit).
## Save writes data/effects.json (and the kept additions) through EditTarget.
##
## Shown for any 3D thing picked (an effect can be added to it); it lists what's
## playing under it first.

const TITLE := "Particles"
const ICON := "effects"
const SECTION := "fx"

var _ed: Node
var _here: OptionButton
var _all: OptionButton
var _add: OptionButton
var _params: FxParams
var _note: Label
var _found: Array = []          # the Fx nodes under the selection
var _t := 0.0


## The picked node (or its anchor, or a parent) has effects under it - or it's a 3D
## thing an effect can be added to.
static func handles(n: Node) -> bool:
	if n == null:
		return false
	if not Fx.under(n).is_empty():
		return true
	var a := n.get_parent()
	while a:
		if a is Fx:
			return true
		a = a.get_parent()
	var anc: Node = LiveEdits.anchor_of(n)[0]
	if anc and not Fx.under(anc).is_empty():
		return true
	return n is Node3D


func bind(ed: Node) -> void:
	_ed = ed
	add_theme_constant_override("separation", 6)
	add_child(UI.section("EFFECTS HERE"))
	_here = OptionButton.new()
	_here.name = "Here"
	_here.focus_mode = FOCUS_NONE
	_here.tooltip_text = EditorIcons.tip("Effects here", "", "The effects playing on what's picked (or on its kind). Pick one to edit its effect.")
	_here.item_selected.connect(func(i): _edit(str(_here.get_item_metadata(i))))
	add_child(_here)
	var row := HBoxContainer.new()
	row.add_child(UI.label("Any effect", 13, UI.TEXT_DIM))
	_all = OptionButton.new()
	_all.name = "All"
	_all.focus_mode = FOCUS_NONE
	_all.size_flags_horizontal = SIZE_EXPAND_FILL
	_all.tooltip_text = EditorIcons.tip("Any effect", "", "Edit any of the game's effects (its every instance changes).")
	_all.item_selected.connect(func(i): _edit(_all.get_item_text(i)))
	row.add_child(_all)
	row.add_child(_btn("Replay", "play", "Plays the effects on what's picked again (one-shots).", replay))
	add_child(row)
	var arow := HBoxContainer.new()
	arow.add_child(UI.label("Add", 13, UI.TEXT_DIM))
	_add = OptionButton.new()
	_add.name = "AddWhich"
	_add.focus_mode = FOCUS_NONE
	_add.size_flags_horizontal = SIZE_EXPAND_FILL
	_add.tooltip_text = EditorIcons.tip("Effect to add", "", "Which effect Add here puts on what's picked.")
	arow.add_child(_add)
	arow.add_child(_btn("Add here", "add", "Attaches the effect to what's picked (at its origin) - kept for every thing of its kind once saved.", func(): add_here(_add.get_item_text(_add.selected))))
	arow.add_child(_btn("Remove added", "delete", "Takes away the effects you added to this kind of thing.", remove_added))
	add_child(arow)
	var srow := HBoxContainer.new()
	srow.add_child(_btn("Save", "save", "Writes the effects (data/effects.json) and what you added - into the game, or the mod picked.", func(): save()))
	_note = UI.label("", 13, UI.TEXT_DIM)
	_note.clip_text = true
	_note.size_flags_horizontal = SIZE_EXPAND_FILL
	srow.add_child(_note)
	add_child(srow)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_params = FxParams.new()
	_params.compact = true
	_params.name = "Params"
	_params.changed.connect(func():
		if _ed and _ed.has_method("edited"):
			_ed.edited(SECTION)
		_show_dirty())
	scroll.add_child(_params)
	size_flags_vertical = SIZE_EXPAND_FILL
	_fill()


func unbind() -> void:
	_ed = null


func live_process(delta: float) -> void:
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	if _ed and Fx.under(_root()).size() != _found.size():
		_fill_here()


func _btn(name: String, icon: String, help: String, cb: Callable) -> Button:
	var b := UI.button("", cb, 14)
	b.focus_mode = FOCUS_NONE
	return EditorIcons.dress(b, icon, EditorIcons.tip(name, "", help))


## Where to look for effects: the selection, or (none under it) its anchor.
func _root() -> Node:
	var sel: Node = _ed.selected if _ed else null
	if sel == null or not is_instance_valid(sel):
		return null
	if not Fx.under(sel).is_empty():
		return sel
	var a: Node = _ed.anchor if _ed.anchor and is_instance_valid(_ed.anchor) else null
	return a if a else sel


func _fill() -> void:
	_all.clear()
	_add.clear()
	for n in Fx.names():
		_all.add_item(n)
		_add.add_item(n)
	_fill_here()
	var first := str(_here.get_item_metadata(0)) if _here.item_count > 0 and _here.get_item_metadata(0) != null else (str(Fx.names()[0]) if not Fx.names().is_empty() else "")
	_edit(first)
	_show_dirty()


func _fill_here() -> void:
	_here.clear()
	_found = Fx.under(_root()) if _ed else []
	for f in _found:
		_here.add_item("%s  (%s)" % [f.effect, "looping" if f.attached else "one-shot"])
		_here.set_item_metadata(_here.item_count - 1, f.effect)
	if _found.is_empty():
		_here.add_item("(none playing here)")
		_here.set_item_metadata(0, null)
		_here.disabled = true
	else:
		_here.disabled = false


func _edit(name: String) -> void:
	if name == "" or not Fx.has(name):
		_params.show_effect("")
		return
	var i := Fx.names().find(name)
	if i >= 0:
		_all.select(i)
		_add.select(i)
	_params.show_effect(name)


## Plays the one-shots on what's picked again.
func replay() -> void:
	for f in Fx.under(_root()):
		f.play()


## Effect `name` attached to what's picked, kept for its kind (LiveEdits "fx").
func add_here(name: String) -> Node3D:
	var sel: Node = _ed.selected if _ed else null
	if sel == null or not is_instance_valid(sel) or not Fx.has(name):
		return null
	var key: String = _ed.key
	var anchor: Node = _ed.anchor
	if key == "" or anchor == null:
		var fx := Fx.attach(name, sel)
		_say("Added - not kept (this isn't part of anything kept).")
		_fill_here()
		return fx
	var sec := LiveEdits.section(key, SECTION)
	var list: Array = sec.get("added", [])
	list.append({"path": LiveEdits.rel_path(anchor, sel), "effect": name, "pos": LiveEdits.enc(Vector3.ZERO)})
	sec["added"] = list
	if _ed.has_method("edited"):
		_ed.edited(SECTION)
	apply_edit(anchor, sec)
	_fill_here()
	_edit(name)
	_say("Added %s to %s." % [name, LiveEditor.kind_name(key)])
	return Fx.under(sel).back() if not Fx.under(sel).is_empty() else null


## Takes away the effects added to this kind of thing (kept ones: from the record too).
func remove_added() -> void:
	if _ed == null or _ed.anchor == null:
		return
	for f in Fx.under(_ed.anchor):
		if str(f.name).begins_with("LiveFx_"):
			f.visible = false
			f.queue_free()
	if _ed.key != "":
		var sec := LiveEdits.section(_ed.key, SECTION)
		sec.erase("added")
		if sec.is_empty():
			LiveEdits.forget(_ed.key, SECTION)
		if _ed.has_method("edited"):
			_ed.edited(SECTION)
	_say("Removed the added effects.")
	_fill_here()


func save() -> bool:
	var ok := true
	if Fx.dirty:
		ok = Fx.save()
	if LiveEdits.dirty:
		ok = LiveEdits.save() and ok
	var et: GDScript = load("res://scripts/editor/edit_target.gd")
	_say(("Saved into %s." if ok else "Can't save into %s: pick a mod.") % et.label())
	return ok


func _say(t: String) -> void:
	if _note:
		_note.text = t
	if _ed and _ed.has_method("say"):
		_ed.say(t)


func _show_dirty() -> void:
	if _note and Fx.dirty:
		_note.text = "effects changed - unsaved"


## Puts back the effects added to this kind of thing (LiveEdits, each time one's made).
static func apply_edit(anchor: Node, data: Dictionary) -> void:
	var list: Array = data.get("added", [])
	for i in list.size():
		var e = list[i]
		if not e is Dictionary or not Fx.has(str(e.get("effect", ""))):
			continue
		var at: Node = LiveEdits.find(anchor, str(e.get("path", ".")))
		var nm := "LiveFx_%d" % i
		if at == null or at.has_node(NodePath(nm)):
			continue
		var fx := Fx.attach(str(e["effect"]), at)
		fx.name = nm
		var p = LiveEdits.dec(e.get("pos"))
		if p is Vector3:
			fx.position = p
