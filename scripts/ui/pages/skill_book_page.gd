extends VBoxContainer
## Field Computer tab: the Spell Book - the automaton's skills (Skills) by
## school (martial arts; movement and the arcana). At the top its level, the
## experience toward the next and the skill points to spend; each skill a row:
## its icon (drag it onto the toolbar, or hover it and press 1-9), its name,
## its rank (five pips) and a button to learn it or raise its rank with a
## point (greyed, with the reason, when it can't be). On the right, the skill
## under the mouse in full: what it does, what it costs, what each rank adds.

var surface: Node

var _head: Label
var _bar: ProgressBar
var _cols: HBoxContainer
var _name: Label
var _text: Label
var _hovered := ""
var _shown := ""
var _sig := 0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	add_child(top)
	_head = UI.label("", 18, Color(1.0, 0.82, 0.4))
	top.add_child(_head)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(220, 14)
	_bar.show_percentage = false
	_bar.size_flags_vertical = SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(1.0, 0.82, 0.4)
	_bar.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.1, 0.12, 0.16)
	_bar.add_theme_stylebox_override("background", back)
	top.add_child(_bar)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	add_child(body)
	_cols = HBoxContainer.new()
	_cols.add_theme_constant_override("separation", 18)
	body.add_child(_cols)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.custom_minimum_size.x = 380
	body.add_child(side)
	_name = UI.section("", NeonTheme.HEAD)
	side.add_child(_name)
	_text = UI.note("", 14, 380.0, NeonTheme.TEXT)
	side.add_child(_text)
	side.add_child(UI.note("Fighting earns experience: enemies defeated, blows and spells that land. Each level gives a skill point. "
		+ "Every use costs stamina.", 12, 380.0))


func refresh() -> void:
	if surface == null:
		return
	var p: Dictionary = surface.state["player"]
	var st: Dictionary = Skills.state(p)
	var lv := int(st["level"])
	var need := Skills.xp_need(lv)
	_head.text = "LEVEL %d   ·   %s   ·   %d skill point%s" % [lv,
		("%d / %d XP" % [int(st["xp"]), need]) if lv < Skills.MAX_LEVEL else "the highest level", int(st["points"]),
		"" if int(st["points"]) == 1 else "s"]
	_bar.max_value = maxf(1.0, need)
	_bar.value = float(st["xp"]) if lv < Skills.MAX_LEVEL else need
	# (the rows rebuilt only when something they show changed)
	var sig := str([st["ranks"], st["points"], lv, surface.foot_toolbar()]).hash()
	if sig == _sig and _cols.get_child_count() > 0:
		return
	_sig = sig
	UI.clear(_cols)
	var col: VBoxContainer = null
	for sc in Skills.SCHOOLS:
		if sc[0] != "arcana":       # (movement and the arcana share the second column)
			col = VBoxContainer.new()
			col.add_theme_constant_override("separation", 5)
			_cols.add_child(col)
		col.add_child(UI.section(str(sc[1]).to_upper(), sc[2]))
		for id in Skills.ORDER:
			if Skills.SKILLS[id]["school"] == sc[0]:
				col.add_child(_card(p, id, sc[2]))
	_describe(_shown if _shown != "" else "pygmachia")
	UI.scale_fonts(self, "menu")


## The skill shown in full on the right.
func _describe(id: String) -> void:
	if not Skills.SKILLS.has(id) or surface == null:
		return
	_shown = id
	var p: Dictionary = surface.state["player"]
	var r := Skills.rank(p, id)
	var s: Dictionary = Skills.SKILLS[id]
	_name.text = "%s   %s" % [str(s["name"]).to_upper(), ("rank %d" % r) if r > 0 else "not learned - needs level %d" % int(s["level"])]
	_name.add_theme_color_override("font_color", Skills.school_color(id))
	_text.text = Skills.describe(id, r)
	if s["kind"] == "style":
		var names := PackedStringArray()
		for m in s["moves"]:
			names.append("%s %d" % [Skills.MOVES[m]["name"], roundi(Skills.blow_damage(m, maxi(1, r)))])
		_text.text += "\nBlows (damage): " + ", ".join(names)


func _card(p: Dictionary, id: String, accent: Color) -> Control:
	var s: Dictionary = Skills.SKILLS[id]
	var r := Skills.rank(p, id)
	var panel := PanelContainer.new()
	var box := NeonTheme.box(Color(accent, 0.55 if r > 0 else 0.22), Color(NeonTheme.BG, 0.6), 1, 6, 8)
	box.content_margin_left = 6
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", box)
	panel.custom_minimum_size.x = 380
	panel.mouse_entered.connect(_describe.bind(id))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var item := Skills.item_of(id)
	var slot := ItemSlot.make(item, 0, 44.0, r <= 0)
	slot.show_count = false
	slot.size_flags_vertical = SIZE_SHRINK_CENTER
	var on_bar: int = surface.foot_toolbar().find(item)
	slot.tooltip_text = "%s\n%s" % [s["name"], ("On toolbar slot %d." % (on_bar + 1)) if on_bar >= 0 else
		("Drag it onto the toolbar, or press 1-9 here." if r > 0 else "Learn it first.")]
	if r > 0:
		slot.payload = {"src": "skills", "id": item}
	slot.hovered.connect(func(i): _hovered = i; _describe(id))
	slot.mouse_exited.connect(func(): _hovered = "")
	row.add_child(slot)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(v)
	var name := UI.label(str(s["name"]), 16, accent if r > 0 else UI.TEXT_DIM)
	name.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(name)
	var pips := ""
	for i in Skills.MAX_RANK:
		pips += "●" if i < r else "○"
	var sub := UI.label(pips + ("    slot %d" % (on_bar + 1) if on_bar >= 0 else ""), 13, accent)
	sub.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(sub)
	var why := Skills.cant_learn(p, id)
	var b := UI.button("Learn" if r <= 0 else ("Rank %d" % (r + 1) if r < Skills.MAX_RANK else "Mastered"), _learn.bind(id), 13)
	b.disabled = why != ""
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	b.tooltip_text = why if why != "" else "Spends 1 skill point."
	b.mouse_entered.connect(_describe.bind(id))
	row.add_child(b)
	return panel


func _learn(id: String) -> void:
	var p: Dictionary = surface.state["player"]
	var first := Skills.rank(p, id) <= 0
	if not Skills.learn(p, id):
		return
	var item := Skills.item_of(id)
	var bar: Array = surface.foot_toolbar()
	if first and not bar.has(item) and bar.has(""):      # (a new skill: onto the first free slot)
		bar[bar.find("")] = item
	GameLog.post("%s: %s" % [Skills.SKILLS[id]["name"], "learned" if first else "rank %d" % Skills.rank(p, id)], "good")
	Sfx.play("skill/levelup", -6.0)
	refresh()


## 1-9 over a skill you know: it goes on that toolbar slot.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _hovered == "" or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode < KEY_1 or event.keycode > KEY_9 or Skills.rank(surface.state["player"], Skills.id_of(_hovered)) <= 0:
		return
	var bar: Array = surface.foot_toolbar()
	var i: int = event.keycode - KEY_1
	var was := bar.find(_hovered)
	if was >= 0:
		bar[was] = ""
	bar[i] = _hovered
	get_viewport().set_input_as_handled()
	refresh()
