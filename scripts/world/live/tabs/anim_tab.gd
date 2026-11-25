extends VBoxContainer
## The Live Editor's Animation tab: the clips of what's picked (its AnimationPlayer)
## - which one's playing and where, any of them played on it now, its speed - and
## the animation editor in a window over the running game, open on its character and
## clip: saved there, a clip changes on every character of that model at once (their
## clips are shared). Kept (LiveEdits, section "anim"): {rel path: {"speed": x}}.

const TITLE := "Animation"
const ICON := "anim"

var ed: Node
var _ap: AnimationPlayer
var _now: Label
var _list: ItemList
var _t := 0.0


static func handles(n: Node) -> bool:
	return _player_of(n) != null


## The AnimationPlayer of `n`'s character: under it, or under the thing it's part of.
static func _player_of(n: Node) -> AnimationPlayer:
	var a := n
	for i in 6:
		if a == null:
			break
		var found := a.find_children("*", "AnimationPlayer", true, false)
		if not found.is_empty():
			return found[0]
		if a.has_meta("edit_key") or a.has_meta("model_id"):
			break
		a = a.get_parent()
	return null


static func model_id(ap: AnimationPlayer) -> String:
	var a: Node = ap
	while a:
		if a.has_meta("model_id"):
			return str(a.get_meta("model_id"))
		a = a.get_parent()
	return ""


func bind(e: Node) -> void:
	ed = e
	_ap = _player_of(ed.selected)
	var id := model_id(_ap)
	add_child(LiveFields.head("CLIPS" + ("  ·  " + id if id != "" else "")))
	_now = UI.label("", 14)
	add_child(_now)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 260
	_list.focus_mode = Control.FOCUS_NONE
	for c in _ap.get_animation_list():
		var a := _ap.get_animation(c)
		_list.add_item("%s   %.2f s%s" % [c, a.length, "  loop" if a.loop_mode != Animation.LOOP_NONE else ""])
		_list.set_item_metadata(_list.item_count - 1, c)
	_list.item_activated.connect(func(i): _ap.play(str(_list.get_item_metadata(i))))
	_list.tooltip_text = "Double-click a clip to play it on this one now."
	add_child(_list)
	var h := HBoxContainer.new()
	var play := UI.button("Play", func():
		var s := _list.get_selected_items()
		if not s.is_empty():
			_ap.play(str(_list.get_item_metadata(s[0]))), 14)
	EditorIcons.dress(play, "play", EditorIcons.tip("Play", "", "Plays the selected clip on this one now (its own behaviour takes over again when it picks its next clip)."))
	play.text = "Play"
	h.add_child(play)
	if id != "" and ResourceLoader.exists(TalosNav.SCENES["anim"]):
		var edit := UI.button("Animation editor", _edit, 14)
		EditorIcons.dress(edit, "anim", EditorIcons.tip("Animation editor", "", "Opens the animation editor over the running game, on this character and its clip. Saved there, the clip changes on every %s at once." % id))
		edit.text = "Animation editor"
		h.add_child(edit)
	add_child(h)
	var rel := LiveEdits.rel_path(ed.anchor, _ap) if ed.anchor else "."
	add_child(LiveFields.row("Speed", _ap.speed_scale, func(v):
		_ap.speed_scale = v
		if ed.key != "":
			var sec := LiveEdits.section(ed.key, "anim")
			sec[rel] = {"speed": v}
			ed.edited("anim"), "0,3,0.01", "How fast its clips play: 1 as made, 0 frozen, 2 twice as fast. Kept for every one of its kind."))


func unbind() -> void:
	ed = null


func _edit() -> void:
	var t: Node = ed.open_tool("anim", "Animation: " + model_id(_ap))
	t.open_character(model_id(_ap))
	if _ap.current_animation != "":
		t.select_clip(_ap.current_animation)


func live_process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or not is_instance_valid(_ap):
		return
	_t = 0.1
	_now.text = ("Playing: %s  %.2f / %.2f s" % [_ap.current_animation, _ap.current_animation_position, _ap.current_animation_length]) if _ap.is_playing() else "Not playing"


static func apply_edit(anchor: Node, data: Dictionary) -> void:
	for rel in data:
		var ap := LiveEdits.find(anchor, str(rel)) as AnimationPlayer
		if ap and data[rel].has("speed"):
			ap.speed_scale = float(data[rel]["speed"])
