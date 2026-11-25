extends Control
## The Scenario Editor (Editor > Scenario Editor, F4): quests written as
## plain-sentence rules - WHEN <event> AND <conditions> THEN <actions> - with
## every word picked from a drop-down (Scenarios defines them). Left: the
## scenarios; top: the selected one's steps (click a step to see only its
## rules); middle: the rules as cards; bottom: problems found in it.
## Test runs a new game with the scenario at the selected step.

const EDITOR_SCENE := "res://editor.tscn"
const ACCENT := Color(1.0, 0.78, 0.35)
const CARD_BG := Color(0.05, 0.06, 0.12, 0.95)

var _list: ItemList
var _title: LineEdit
var _id: LineEdit
var _desc: TextEdit
var _enabled: CheckBox
var _steps_bar: HFlowContainer
var _rules_box: VBoxContainer
var _rules_scroll: ScrollContainer
var _problems: RichTextLabel
var _status: Label
var _sc := {}                 # the scenario being edited (lives in Scenarios' data)
var _step_filter := ""        # "" = every rule
var dirty := false
var _gen := 0   # (each rebuild's number: an older one still adding cards stops)


func _ready() -> void:
	NeonTheme.set_empire("")
	if Galaxy.systems.is_empty():
		Galaxy.new_game(false, true)   # (the map only: Talos lists its places, never runs it)
	Galaxy.active = false
	Scenarios.reload_if_changed()
	_build()
	_refresh_list()
	if not Scenarios.all().is_empty():
		_select(0)
	PinTips.install(self, "scenarios")


# --- Layout --------------------------------------------------------------------------

func _build() -> void:
	var root := TalosNav.wrap(UI.modal(self, ACCENT, Vector2.ZERO, true), "scenarios", _go)
	var hn := TalosNav.header("SCENARIOS", "Each rule reads: WHEN something happens AND these are true THEN do these. Click the words to change them; hover anything for help.", ACCENT)
	var header: HBoxContainer = hn[0]
	_status = hn[1]
	header.add_child(_icon_btn("Test in game", "play", "F5", "Starts a new game with this scenario running, already at the selected\nstep (or its first). Unsaved edits are used too. Return through the menu.", _test))
	header.add_child(_icon_btn("Save", "save", "Ctrl+S", "Writes every scenario to data/scenarios.json. New games use them.", _save))
	header.add_child(_icon_btn("Reload", "reload", "Ctrl+R", "Throws away unsaved edits and reads data/scenarios.json again.", _reload))
	header.add_child(EditorIcons.docs_button(self, "scenarios"))
	root.add_child(header)
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	# Left: scenarios.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	body.add_child(left)
	left.add_child(UI.label("SCENARIOS", 16, ACCENT))
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_select)
	_list.tooltip_text = EditorIcons.tip("Scenarios", "", "Every quest scenario. Pick one to edit its steps and rules.\nGreyed ones are disabled (they don't start in new games).")
	left.add_child(_list)
	var lb := HBoxContainer.new()
	left.add_child(lb)
	lb.add_child(_icon_btn("New scenario", "add", "Ctrl+N", "Adds an empty scenario with the steps 'Not started' and 'Finished'.", _new_scenario))
	lb.add_child(_icon_btn("Duplicate", "duplicate", "", "Copies the selected scenario (rules and all).", _duplicate))
	lb.add_child(_icon_btn("Delete", "delete", "", "Deletes the selected scenario (Reload brings it back if you haven't saved).", _delete))
	lb.add_child(_icon_btn("Import the main quest", "quest", "", "Writes the main quest (The Thread of Ariadne) as a rules scenario -\na complete worked example of every kind of objective. It starts disabled:\nthe story keeps running on its own system.", _import_main))
	left.add_child(UI.label("Title", 14, UI.TEXT_DIM))
	_title = LineEdit.new()
	_title.text_changed.connect(func(t): _sc["title"] = t; _touch(); _refresh_list())
	left.add_child(_title)
	left.add_child(UI.label("Id (used by 'start scenario' and saves)", 14, UI.TEXT_DIM))
	_id = LineEdit.new()
	_id.text_changed.connect(func(t): _sc["id"] = t.strip_edges().to_snake_case(); _touch())
	left.add_child(_id)
	left.add_child(UI.label("Description (for you)", 14, UI.TEXT_DIM))
	_desc = TextEdit.new()
	_desc.custom_minimum_size = Vector2(0, 90)
	_desc.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_desc.text_changed.connect(func(): _sc["description"] = _desc.text; _touch())
	left.add_child(_desc)
	_enabled = CheckBox.new()
	_enabled.text = "Enabled: starts with every new game"
	_enabled.tooltip_text = EditorIcons.tip("Enabled", "", "On: the scenario starts with every new game (its 'the scenario starts' rules\nfire). Off: only a 'start scenario' action (or Test) starts it.")
	_enabled.toggled.connect(func(on): _sc["enabled"] = on; _touch(); _refresh_list())
	left.add_child(_enabled)
	# Right: steps, rules, problems.
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	right.add_child(UI.label("STEPS  ·  click one to see only its rules (and to make new rules for it)", 16, ACCENT))
	_steps_bar = HFlowContainer.new()
	_steps_bar.add_theme_constant_override("h_separation", 6)
	_steps_bar.add_theme_constant_override("v_separation", 6)
	right.add_child(_steps_bar)
	_rules_scroll = ScrollContainer.new()
	_rules_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rules_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(_rules_scroll)
	_rules_box = VBoxContainer.new()
	_rules_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rules_box.add_theme_constant_override("separation", 10)
	_rules_scroll.add_child(_rules_box)
	right.add_child(UI.label("PROBLEMS", 14, ACCENT))
	_problems = RichTextLabel.new()
	_problems.bbcode_enabled = true
	_problems.custom_minimum_size = Vector2(0, 90)
	_problems.scroll_active = true
	right.add_child(_problems)


func _icon_btn(title: String, icon: String, keys: String, body: String, cb: Callable) -> Button:
	var b := UI.button("", cb, 16)
	EditorIcons.dress(b, icon, EditorIcons.tip(title, keys, body))
	b.focus_mode = Control.FOCUS_NONE
	return b


func _small(text: String, cb: Callable, tip := "") -> Button:
	var b := UI.button(text, cb, 13)
	b.focus_mode = Control.FOCUS_NONE
	if tip != "":
		b.tooltip_text = tip
	return b


# --- Scenarios list ----------------------------------------------------------------------

func _refresh_list() -> void:
	var keep := _list.get_selected_items()
	_list.clear()
	for sc in Scenarios.all():
		var i := _list.add_item(str(sc.get("title", sc.get("id", "?"))))
		if not bool(sc.get("enabled", true)):
			_list.set_item_custom_fg_color(i, Color(0.55, 0.6, 0.7))
			_list.set_item_text(i, _list.get_item_text(i) + "  (disabled)")
	if not keep.is_empty() and keep[0] < _list.item_count:
		_list.select(keep[0])


func _select(i: int) -> void:
	if i < 0 or i >= Scenarios.all().size():
		return
	_sc = Scenarios.all()[i]
	_list.select(i)
	_title.set_block_signals(true)
	_id.set_block_signals(true)
	_desc.set_block_signals(true)
	_enabled.set_block_signals(true)
	_title.text = str(_sc.get("title", ""))
	_id.text = str(_sc.get("id", ""))
	_desc.text = str(_sc.get("description", ""))
	_enabled.button_pressed = bool(_sc.get("enabled", true))
	for c in [_title, _id, _desc, _enabled]:
		c.set_block_signals(false)
	_step_filter = ""
	_rebuild()


func _new_scenario() -> void:
	var n := Scenarios.all().size() + 1
	var sc := Scenarios.blank("scenario_%d" % n, "New scenario %d" % n)
	Scenarios.all().append(sc)
	_touch()
	_refresh_list()
	_select(Scenarios.all().size() - 1)


func _duplicate() -> void:
	if _sc.is_empty():
		return
	var c: Dictionary = _sc.duplicate(true)
	c["id"] = str(c["id"]) + "_copy"
	c["title"] = str(c["title"]) + " (copy)"
	Scenarios.all().append(c)
	_touch()
	_refresh_list()
	_select(Scenarios.all().size() - 1)


func _delete() -> void:
	if _sc.is_empty():
		return
	UI.confirm(self, "Delete '%s'?" % _sc.get("title", ""), "The scenario and all its rules are removed (Reload brings it back until you save).", func():
		Scenarios.all().erase(_sc)
		_sc = {}
		_touch()
		_refresh_list()
		if not Scenarios.all().is_empty():
			_select(0)
		else:
			_rebuild(), "Delete", "Keep it")


func _import_main() -> void:
	var sc := Scenarios.from_main_quest()
	for i in Scenarios.all().size():
		if Scenarios.all()[i].get("id") == sc["id"]:
			Scenarios.all()[i] = sc
			_touch()
			_refresh_list()
			_select(i)
			return
	Scenarios.all().append(sc)
	_touch()
	_refresh_list()
	_select(Scenarios.all().size() - 1)
	_status.text = "Imported the main quest as '%s' (disabled): %d steps, %d rules." % [sc["title"], sc["steps"].size(), sc["rules"].size()]


# --- Steps ---------------------------------------------------------------------------------

func _build_steps() -> void:
	for c in _steps_bar.get_children():
		c.queue_free()
	if _sc.is_empty():
		return
	var steps: Array = _sc["steps"]
	var all := _step_chip("All rules (%d)" % (_sc["rules"] as Array).size(), _step_filter == "", func(): _step_filter = ""; _rebuild())
	all.tooltip_text = EditorIcons.tip("All rules", "", "Shows every rule of the scenario.")
	_steps_bar.add_child(all)
	for i in steps.size():
		var st: String = steps[i]
		var n := _rules_for_step(st).size()
		var chip := _step_chip("%d · %s (%d)" % [i + 1, st, n], _step_filter == st, func(): _step_filter = st; _rebuild())
		chip.tooltip_text = EditorIcons.tip("Step: " + st, "", "Shows the rules that test 'the quest step is %s' (or wait for it).\nNew rules made now are for this step." % st)
		_steps_bar.add_child(chip)
	var name_edit := LineEdit.new()
	name_edit.placeholder_text = "step name"
	name_edit.custom_minimum_size = Vector2(160, 0)
	_steps_bar.add_child(name_edit)
	_steps_bar.add_child(_small("+ Add step", func():
		var t := name_edit.text.strip_edges()
		if t == "" or steps.has(t):
			t = "Step %d" % steps.size()
		steps.insert(maxi(steps.size() - 1, 0), t)   # before "Finished"
		_step_filter = t
		_touch()
		_rebuild(), EditorIcons.tip("Add step", "", "Adds a step (named in the box) before the last one.")))
	if _step_filter != "":
		_steps_bar.add_child(_small("Rename", func():
			var t := name_edit.text.strip_edges()
			if t == "" or steps.has(t):
				return
			_rename_step(_step_filter, t), EditorIcons.tip("Rename step", "", "Renames the selected step to the name in the box - in every rule that uses it.")))
		_steps_bar.add_child(_small("◀", func(): _move_step(-1), "Moves the selected step earlier."))
		_steps_bar.add_child(_small("▶", func(): _move_step(1), "Moves the selected step later."))
		_steps_bar.add_child(_small("Delete step", func():
			steps.erase(_step_filter)
			_step_filter = ""
			_touch()
			_rebuild(), "Removes the selected step (its rules stay: the problems list shows what refers to it)."))


func _step_chip(text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _rules_for_step(st: String) -> Array:
	var out := []
	var rules: Array = _sc["rules"]
	for i in rules.size():
		var r: Dictionary = rules[i]
		var ev: Dictionary = r.get("when", {})
		var hit: bool = ev.get("event") == "step" and ev.get("args", {}).get("step") == st
		for c in r.get("if", []):
			if c.get("cond") == "step_is" and c.get("args", {}).get("step") == st:
				hit = true
		if hit:
			out.append(i)
	return out


func _rename_step(old: String, new: String) -> void:
	var steps: Array = _sc["steps"]
	steps[steps.find(old)] = new
	for r in _sc["rules"]:
		for part in [[r.get("when", {})], r.get("if", []), r.get("then", [])]:
			for e in part:
				var a: Dictionary = e.get("args", {})
				if a.get("step") == old:
					a["step"] = new
	_step_filter = new
	_touch()
	_rebuild()


func _move_step(d: int) -> void:
	var steps: Array = _sc["steps"]
	var i := steps.find(_step_filter)
	var j := i + d
	if i < 0 or j < 0 or j >= steps.size():
		return
	steps[i] = steps[j]
	steps[j] = _step_filter
	_touch()
	_rebuild()


# --- Rules ---------------------------------------------------------------------------------

func _rebuild() -> void:
	var keep := _rules_scroll.scroll_vertical
	_build_steps()
	for c in _rules_box.get_children():
		c.queue_free()
	if _sc.is_empty():
		_problems.text = ""
		return
	var rules: Array = _sc["rules"]
	var shown: Array = range(rules.size()) if _step_filter == "" else _rules_for_step(_step_filter)
	# The cards one a frame (each ~15 ms to build and lay out): the screen
	# answers at once and the rules fill in, instead of one long frame.
	_gen += 1
	var gen := _gen
	var first := true
	for i in shown:
		if not first:
			await get_tree().process_frame
			if gen != _gen or not is_inside_tree():
				return   # (rebuilt again meanwhile)
		first = false
		_rules_box.add_child(_card(i))
	var add := _small("+ New rule" + ("  (for step '%s')" % _step_filter if _step_filter != "" else ""), func():
		rules.append(Scenarios.blank_rule(_step_filter))
		_touch()
		_rebuild()
		await get_tree().process_frame
		_rules_scroll.scroll_vertical = int(_rules_scroll.get_v_scroll_bar().max_value), \
		EditorIcons.tip("New rule", "Ctrl+Enter", "Adds a rule: WHEN the player docks... - change every word with its drop-down.\nWith a step selected, the rule starts with 'AND the quest step is <that step>'."))
	_rules_box.add_child(add)
	_check()
	await get_tree().process_frame
	_rules_scroll.scroll_vertical = keep


func _card(i: int) -> Control:
	var rules: Array = _sc["rules"]
	var r: Dictionary = rules[i]
	var card := PanelContainer.new()
	var st: NeonBox = UI.panel_style(Color(ACCENT, 0.55))
	st.bg_color = CARD_BG
	card.add_theme_stylebox_override("panel", st)
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	card.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	# Header: number, note, once, move / copy / delete.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UI.label("RULE %d" % (i + 1), 15, ACCENT))
	var note := LineEdit.new()
	note.placeholder_text = "note (what this rule is for)"
	note.text = str(r.get("note", ""))
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.text_changed.connect(func(t): r["note"] = t; _touch())
	head.add_child(note)
	var once := CheckBox.new()
	once.text = "only once"
	once.button_pressed = bool(r.get("once", true))
	once.tooltip_text = EditorIcons.tip("Only once", "", "On: the rule runs the first time it matches, then never again.\nOff: it runs every time (e.g. a message every time you dock while a step lasts).")
	once.toggled.connect(func(on): r["once"] = on; _touch())
	head.add_child(once)
	head.add_child(_small("▲", func(): _move_rule(i, -1), "Moves the rule up (rules run in this order when several match)."))
	head.add_child(_small("▼", func(): _move_rule(i, 1), "Moves the rule down."))
	head.add_child(_small("Copy", func():
		rules.insert(i + 1, r.duplicate(true))
		_touch()
		_rebuild(), "Duplicates the rule just below."))
	head.add_child(_small("✕", func():
		rules.remove_at(i)
		_touch()
		_rebuild(), "Deletes the rule."))
	# WHEN
	var ev: Dictionary = r["when"]
	v.add_child(_line("WHEN", Scenarios.EVENTS, ev, "event", "Choose what has to happen for this rule to run."))
	# AND
	var conds: Array = r["if"]
	for k in conds.size():
		var row := _line("AND", Scenarios.CONDITIONS, conds[k], "cond", "A condition that must also be true.")
		row.add_child(_small("✕", func(): conds.remove_at(k); _touch(); _rebuild(), "Removes this condition."))
		v.add_child(row)
	v.add_child(_compact(_small("+ condition", func():
		conds.append({"cond": "step_is", "args": {"step": _step_filter if _step_filter != "" else _first_step()}})
		_touch()
		_rebuild(), "Adds an AND condition (all of them must be true).")))
	# THEN
	var acts: Array = r["then"]
	for k in acts.size():
		var row := _line("THEN" if k == 0 else "   ·", Scenarios.ACTIONS, acts[k], "action", "What happens: actions run in order, top to bottom.")
		row.add_child(_small("▲", func():
			if k > 0:
				var t = acts[k - 1]
				acts[k - 1] = acts[k]
				acts[k] = t
				_touch()
				_rebuild(), "Moves this action earlier."))
		row.add_child(_small("✕", func(): acts.remove_at(k); _touch(); _rebuild(), "Removes this action."))
		v.add_child(row)
	v.add_child(_compact(_small("+ action", func():
		acts.append({"action": "message", "args": {"text": "..."}})
		_touch()
		_rebuild(), "Adds a THEN action.")))
	return card


func _compact(b: Control) -> Control:
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return b


func _first_step() -> String:
	var steps: Array = _sc.get("steps", [])
	return steps[0] if not steps.is_empty() else ""


func _move_rule(i: int, d: int) -> void:
	var rules: Array = _sc["rules"]
	var j := i + d
	if j < 0 or j >= rules.size():
		return
	var t = rules[i]
	rules[i] = rules[j]
	rules[j] = t
	_touch()
	_rebuild()


## One sentence line: a keyword, the kind picker, then the sentence with its
## argument widgets in place.
func _line(word: String, table: Dictionary, entry: Dictionary, key: String, tip: String) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 6)
	var w := UI.label(word, 15, ACCENT if word != "   ·" else UI.TEXT_DIM)
	w.custom_minimum_size = Vector2(56, 0)
	row.add_child(w)
	var ids: Array = table.keys()
	var pick := _lazy_pick(ids.map(func(x): return _short(table[x][0])), maxi(ids.find(entry.get(key, "")), 0))
	pick.tooltip_text = EditorIcons.tip(word.strip_edges().replace("·", "THEN"), "", tip + "\nPicking another keeps the arguments that still apply.")
	pick.item_selected.connect(func(i):
		entry[key] = ids[i]
		var old: Dictionary = entry.get("args", {})
		var args := {}
		for a in table[ids[i]][1]:
			if old.has(a):
				args[a] = old[a]
		entry["args"] = args
		_touch()
		_rebuild())
	row.add_child(pick)
	var id: String = entry.get(key, ids[0])
	if not table.has(id):
		return row
	if not entry.has("args"):
		entry["args"] = {}
	var args: Dictionary = entry["args"]
	# The sentence, split at its {arguments}.
	var s: String = table[id][0]
	var types: Dictionary = table[id][1]
	var re := RegEx.create_from_string("\\{(\\w+)\\}")
	var pos := 0
	for mt in re.search_all(s):
		var before := s.substr(pos, mt.get_start() - pos).strip_edges()
		if before != "" and pos > 0:
			row.add_child(UI.label(before, 14, UI.TEXT_DIM))
		var a := mt.get_string(1)
		row.add_child(_arg_widget(types.get(a, "text"), args, a))
		pos = mt.get_end()
	var tail := s.substr(pos).strip_edges()
	if tail != "" and pos > 0:
		row.add_child(UI.label(tail, 14, UI.TEXT_DIM))
	return row


## The fixed words of a sentence up to its first argument (the picker's text).
func _short(sentence: String) -> String:
	var i := sentence.find("{")
	return (sentence.substr(0, i) if i > 0 else sentence).strip_edges().trim_suffix("\"").strip_edges()


# --- Argument widgets ---------------------------------------------------------------------

func _choices(type: String) -> Array:
	match type:
		"station":
			var names := {}
			for sid in Galaxy.stations:
				names[str(Galaxy.stations[sid]["name"])] = str(Galaxy.SYSTEMS[Galaxy.stations[sid]["system"]]["name"])
			var out := [["any", "any station"]]
			for n in names:
				out.append([n, "%s (%s)" % [n, names[n]]])
			return out
		"system": return Galaxy.SYSTEMS.keys().map(func(k): return [k, Galaxy.SYSTEMS[k]["name"]])
		"planet": return Planets.PLANETS.keys().map(func(k): return [k, Planets.PLANETS[k]["name"]])
		"item": return Items.ITEMS.keys().map(func(k): return [k, Items.display_name(k)])
		"ship_type":
			var t := EnemyTypes.types()
			return [["any", "any ship"]] + t.keys().map(func(k): return [k, str(t[k].get("name", k))])
		"empire": return Galaxy.EMPIRES.keys().map(func(k): return [k, Galaxy.EMPIRES[k]["name"]])
		"state": return Galaxy.STATES.keys().map(func(k): return [k, str(Galaxy.STATES[k].get("name", k))])
		"tier": return Galaxy.REP_TIERS.map(func(t): return [t[0], t[0]])
		"op": return Scenarios.OPS.map(func(o): return [o, o])
		"status": return Scenarios.STATUSES.map(func(o): return [o, o])
		"beacon": return Scenarios.BEACONS.map(func(o): return [o, o + " beacon" if o != "none" else "no beacon"])
		"lore": return QuestData.LORE.keys().map(func(k): return [k, QuestData.LORE[k]["title"]])
		"scenario": return Scenarios.all().map(func(s): return [s["id"], s.get("title", s["id"])])
		"step": return (_sc.get("steps", []) as Array).map(func(s): return [s, s])
	return []


func _arg_widget(type: String, args: Dictionary, a: String) -> Control:
	match type:
		"number":
			var sb := SpinBox.new()
			sb.min_value = -1000000
			sb.max_value = 1000000
			sb.step = 1
			sb.allow_greater = true
			sb.allow_lesser = true
			sb.value = float(args.get(a, _default_number(a)))
			args[a] = sb.value
			sb.custom_minimum_size = Vector2(100, 0)
			sb.value_changed.connect(func(x): args[a] = x; _touch())
			return sb
		"text", "group", "marker", "timer", "var":
			var le := LineEdit.new()
			le.text = str(args.get(a, {"group": "raiders", "marker": "target", "timer": "countdown", "var": "count"}.get(type, "")))
			args[a] = le.text
			le.custom_minimum_size = Vector2(320 if type == "text" else 130, 0)
			le.placeholder_text = type
			le.tooltip_text = EditorIcons.tip(type.capitalize(), "", {"group": "A name for these ships: 'every ship of group <name> is destroyed' waits for them.",
				"marker": "A name for this marker: places can then say 'marker:<name>'.", "timer": "A name for the timer: 'timer <name> runs out' fires when it ends.",
				"var": "A counter's name: set, add to and test it (it starts at 0)."}.get(type, "The text to show."))
			le.text_changed.connect(func(t): args[a] = t; _touch())
			return le
		"lines":
			var lines: Array = args.get(a, [])
			args[a] = lines
			var b := Button.new()
			b.text = "dialogue (%d lines)" % lines.size()
			b.tooltip_text = EditorIcons.tip("Dialogue", "", "Click to write the lines: one per line, 'Speaker: text' (BBCode like [b]bold[/b] works).")
			b.pressed.connect(func(): _edit_lines(args, a, b))
			return b
		"place":
			return _place_widget(args, a)
	var ch := _choices(type)
	var cur := str(args.get(a, ch[0][0] if not ch.is_empty() else ""))
	var sel := ch.map(func(c): return str(c[0])).find(cur)
	if sel < 0 and cur != "":
		ch.append([cur, cur + " (?)"])
		sel = ch.size() - 1
	var ob := _lazy_pick(ch.map(func(c): return str(c[1])), maxi(sel, 0))
	args[a] = cur
	ob.item_selected.connect(func(i): args[a] = ch[i][0]; _touch(); _check())
	return ob


## A drop-down that holds only its current choice until it's opened, then
## fills in the rest (`labels`, in order - item_selected's index is theirs).
## A scenario's rules have dozens of drop-downs, some listing every station
## or system: filled up front, picking a scenario took ~400 ms.
func _lazy_pick(labels: Array, sel: int) -> OptionButton:
	var ob := OptionButton.new()
	ob.fit_to_longest_item = false
	if labels.is_empty():
		return ob
	sel = clampi(sel, 0, labels.size() - 1)
	ob.add_item(str(labels[sel]))
	var fill := func():
		if ob.has_meta("filled"):
			return
		ob.set_meta("filled", true)
		ob.clear()
		for l in labels:
			ob.add_item(str(l))
		ob.select(sel)
	ob.button_down.connect(fill)
	ob.get_popup().about_to_popup.connect(fill)
	return ob


func _default_number(a: String) -> float:
	return {"count": 1, "distance": 300, "seconds": 30, "amount": 100, "percent": 50, "value": 1}.get(a, 0)


func _place_widget(args: Dictionary, a: String) -> Control:
	var box := HBoxContainer.new()
	var cur := str(args.get(a, "player"))
	args[a] = cur
	var kinds := [["player", "the player"], ["station", "station"], ["planet", "planet"], ["gate", "gate to"], ["marker", "marker"], ["point", "point x,y"]]
	var kind := cur.get_slice(":", 0)
	var val := cur.substr(kind.length() + 1)
	var ob := OptionButton.new()
	for i in kinds.size():
		ob.add_item(kinds[i][1])
		if kinds[i][0] == kind:
			ob.select(i)
	ob.tooltip_text = EditorIcons.tip("Place", "", "Where: around the player, by a station, near a planet, at a jump gate,\nat a marker placed earlier, or at a point (x, y) in the system.")
	box.add_child(ob)
	var sub: Control
	match kind:
		"station", "planet", "gate":
			var ch := _choices({"station": "station", "planet": "planet", "gate": "system"}[kind])
			if kind == "station":
				ch = ch.slice(1)
			var o := _lazy_pick(ch.map(func(c): return str(c[1])), maxi(ch.map(func(c): return str(c[0])).find(val), 0))
			if val == "" and not ch.is_empty():
				args[a] = kind + ":" + str(ch[0][0])
			o.item_selected.connect(func(i): args[a] = kind + ":" + str(ch[i][0]); _touch())
			sub = o
		"marker", "point":
			var le := LineEdit.new()
			le.text = val if val != "" else ("target" if kind == "marker" else "0,0")
			args[a] = kind + ":" + le.text
			le.custom_minimum_size = Vector2(120, 0)
			le.text_changed.connect(func(t): args[a] = kind + ":" + t; _touch())
			sub = le
	if sub:
		box.add_child(sub)
	ob.item_selected.connect(func(i):
		args[a] = kinds[i][0] + ("" if kinds[i][0] == "player" else ":")
		_touch()
		_rebuild())
	return box


func _edit_lines(args: Dictionary, a: String, b: Button) -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Dialogue - one line each: Speaker: text"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var te := TextEdit.new()
	te.custom_minimum_size = Vector2(900, 300)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.syntax_highlighter = RichField.tag_highlighter()   # (the formatting tags dimmed)
	var lines: Array = args.get(a, [])
	te.text = "\n".join(lines.map(func(l): return ("%s: %s" % [l[0], l[1]]) if l is Array else str(l)))
	box.add_child(te)
	# As the player will read it: the speaker, then the line - bold, italic, colours.
	box.add_child(UI.label("As the player reads it:", 13, UI.TEXT_DIM))
	var preview := RichTextLabel.new()
	preview.bbcode_enabled = true
	preview.custom_minimum_size = Vector2(900, 180)
	var show := func():
		preview.text = "\n".join(Scenarios._lines(te.text).map(func(l): return "[color=#ffcf6a]%s[/color]  %s" % [l[0], l[1]] if l is Array else str(l)))
	te.text_changed.connect(show)
	show.call()
	box.add_child(preview)
	dlg.add_child(box)
	dlg.confirmed.connect(func():
		args[a] = Scenarios._lines(te.text)
		b.text = "dialogue (%d lines)" % (args[a] as Array).size()
		_touch()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered()


# --- Problems, saving, testing ------------------------------------------------------------

func _check() -> void:
	if _sc.is_empty():
		return
	var probs := Scenarios.check(_sc)
	_problems.text = "[color=#80e0a0]No problems found.[/color]" if probs.is_empty() else "\n".join(probs.map(func(p): return "[color=#ffb060]•[/color] " + p))


func _touch() -> void:
	dirty = true
	_check()


func _save() -> void:
	var p := Scenarios.save()
	dirty = false
	_status.text = ("Saved %d scenarios to %s" % [Scenarios.all().size(), p]) if p != "" else "Could not save!"


func _reload() -> void:
	Scenarios.reload()
	dirty = false
	_refresh_list()
	if not Scenarios.all().is_empty():
		_select(0)
	else:
		_sc = {}
		_rebuild()
	_status.text = "Reloaded data/scenarios.json."


func _test() -> void:
	if _sc.is_empty():
		return
	Scenarios.test_request = {"id": _sc["id"], "step": _step_filter}
	SaveGame.pending = {}
	SaveGame.travelling = false
	SaveGame.close_talos()   # (Talos over a game: closed - the test game takes the game's place)
	SaveGame.talos_return = false   # (a test game now: no game to go back to)
	get_tree().change_scene_to_file("res://main.tscn")


## Talos's rail: to another tool (asks about unsaved changes first).
func _go(id: String) -> void:
	TalosNav.go(get_tree(), id, guard)


## Asks about unsaved changes (save / discard / stay), then `then`.
func guard(then: Callable) -> void:
	_back(then)


func _back(then := Callable()) -> void:
	if not then.is_valid():
		TalosNav.go(get_tree(), "menu", guard)   # (Esc: as the rail's Exit)
		return
	var go := then
	if dirty:
		UI.unsaved(self, "The scenarios", func(): _save(), func(): Scenarios.reload(), go)
	else:
		go.call()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var act := Callable()
	if k.keycode == KEY_ESCAPE:
		act = _back
	elif k.ctrl_pressed and k.keycode == KEY_S:
		act = _save
	elif k.ctrl_pressed and k.keycode == KEY_R:
		act = _reload
	elif k.ctrl_pressed and k.keycode == KEY_N:
		act = _new_scenario
	elif k.keycode == KEY_F5:
		act = _test
	elif k.keycode == KEY_F1:
		act = func(): EditorDocs.open(self, "scenarios", EditorDocs.FILE)
	if act.is_valid():
		get_viewport().set_input_as_handled()
		act.call()
