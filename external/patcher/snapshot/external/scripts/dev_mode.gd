class_name DevMode
extends Control
## Talos, the game-data editor (main menu > Talos): edit the main quest's dialogue,
## objectives, rewards, chapters and lore and the NPC interaction texts, and
## browse the sprites (SPRITES tab: data/sprites/*.png, cut from
## external/images/ by tools/extract_sprites.py; "Reload sprites" picks up
## new ones). "Save to file" writes data/main_quest.json and
## data/interactions.json. "Open the Library" shows every asset animated (Library).

signal closed
signal zoo_requested
signal scenario_requested
signal svg_requested
signal patcher_requested

const TABS := ["DIALOGUE", "CHAPTERS", "LORE", "CITIZENS", "SPRITES"]
const ACCENT := Color(1.0, 0.55, 0.25)

## The dialogue box used to preview a stage's dialogue.
var dialogue: Control
## Pause the tree while open (when shown over a running game).
var pause_game := false
## Unsaved edits (any field changed, lines added / moved / deleted).
var dirty := false:
	set(v):
		dirty = v
		if v:
			_edits += 1   # (built pages older than this are built again when shown)
## Edits so far (pages built before the latest are stale: show_tab).
var _edits := 0
## Each page, once built: index -> {box, actions, inner, status, edits}.
## Showing a page shows its box; it's built again only when stale.
var _pages := {}
var _body: VBoxContainer       # (the scroll's child, holding the pages' boxes)
var _actions_bar: HBoxContainer
var current := 0
var _stage := 0
var _lore_id := ""
var _scroll: ScrollContainer
var _content: VBoxContainer
var _status: Label
var _title: Label
var _nav: VBoxContainer
var _actions: HBoxContainer
var _docs: Button
## The Sprites page's thumbnails (built on the first visit, then kept).
var _sprites: VBoxContainer
## The scrolling right side of the Dialogue and Lore pages.
var _inner: ScrollContainer
var _paused_by_me := false
var _built := false


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	process_mode = PROCESS_MODE_ALWAYS


func open() -> void:
	if not _built:
		_build()
	current = clampi(TalosNav.page, 0, TABS.size() - 1)
	_paused_by_me = pause_game and not get_tree().paused
	if _paused_by_me:
		get_tree().paused = true
	show()
	show_tab(current)


## Leaves the editor (then `then`, if given): asks first about unsaved changes.
func leave(then := Callable()) -> void:
	var go := func():
		if then.is_valid():
			then.call()
		else:
			close()
	if dirty:
		UI.unsaved(self, "The quest and interaction data", _save, _reload, go)
	else:
		go.call()


func _exit_tree() -> void:
	if is_instance_valid(_sprites) and _sprites.get_parent() == null:
		_sprites.free()


## Asks about unsaved changes (save / discard / stay), then `then`.
func guard(then: Callable) -> void:
	leave(then)


## To another tool: in Talos straight there (this page stays as it is);
## on its own, asking about unsaved changes first.
func _switch(to: Callable) -> void:
	if TalosNav.host(get_tree()):
		to.call()
	else:
		leave(to)


func close() -> void:
	hide()
	if _paused_by_me:
		get_tree().paused = false
	closed.emit()


func _input(event: InputEvent) -> void:
	if not visible or (dialogue and dialogue.visible):
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()   # (before: leaving may free the scene)
		var f := get_viewport().gui_get_focus_owner()
		if f is TextEdit or f is LineEdit:
			f.release_focus()   # (typing: Esc only stops it - a RichField shows its formatted text; Esc again leaves)
			return
		TalosNav.go(get_tree(), "menu", guard)
		return
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	var act := Callable()
	if k.ctrl_pressed and k.keycode >= KEY_1 and k.keycode < KEY_1 + TABS.size():
		act = show_tab.bind(k.keycode - KEY_1)
	elif k.ctrl_pressed and k.keycode == KEY_S:
		act = _save
	elif k.ctrl_pressed and k.keycode == KEY_R:
		act = _reload
	elif k.ctrl_pressed and k.keycode == KEY_P and current == 0:
		act = func(): _preview(QuestData.STAGES[_stage].get("dialogue", []))
	elif k.keycode == KEY_F4:
		act = _switch.bind(scenario_requested.emit)
	elif k.keycode == KEY_F6:
		act = _switch.bind(svg_requested.emit)
	elif k.keycode == KEY_F7:
		act = _switch.bind(patcher_requested.emit)
	elif k.keycode == KEY_F3:
		act = _switch.bind(zoo_requested.emit)
	elif k.keycode == KEY_F1:
		act = func(): EditorDocs.open(self, ["dialogue", "quest", "lore", "interactions", "sprites"][current], EditorDocs.FILE)
	if act.is_valid():
		get_viewport().set_input_as_handled()   # (before: the action may leave the scene)
		act.call()


func _build() -> void:
	_built = true
	var go := func(id: String):
		if id in TalosNav.PAGES:
			show_tab(TalosNav.PAGES.find(id))
		else:
			TalosNav.go(get_tree(), id, guard)   # (in Talos: just shown; "menu": leaving asks)
	var root := TalosNav.wrap(UI.modal(self, ACCENT, Vector2.ZERO, true), "dialogue", go, false)
	_nav = root.get_parent().get_node("TalosNav")
	var hn := TalosNav.header("DIALOGUE", "", ACCENT)
	var header: HBoxContainer = hn[0]
	_title = header.get_node("TalosTitle")
	_status = hn[1]
	_actions_bar = HBoxContainer.new()
	header.add_child(_actions_bar)
	header.add_child(EditorIcons.dress(UI.button("Save to file", _save, 16), "save",
		EditorIcons.tip("Save to file", "Ctrl+S", "Writes the quest (dialogue, stages, chapters, lore) to data/main_quest.json and the citizens' lines to data/interactions.json.\nEdits already apply in this session; saving keeps them.")))
	header.add_child(EditorIcons.dress(UI.button("Reload file", _reload, 16), "reload",
		EditorIcons.tip("Reload from file", "Ctrl+R", "Throws away every unsaved edit in all pages and reads data/main_quest.json and data/interactions.json again.\nUse it to undo a session of edits; it can't itself be undone.")))
	_docs = EditorIcons.docs_button(self, "data-editor")
	header.add_child(_docs)
	root.add_child(header)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = SIZE_EXPAND_FILL
	_body.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.add_child(_body)


## What each page is for (under its name, until a status message replaces it).
const PAGE_NOTES := ["the main quest's stages: objective, rewards and the dialogue that plays when each starts",
	"the main quest's chapter titles, as shown in the Ship Computer",
	"the lore entries the player unlocks during the quest",
	"what Minoan citizens say when you click them, and its translation",
	"every sprite of the game by group - hover one for its key and file"]


func show_tab(index: int) -> void:
	current = index
	TalosNav.page = index
	TalosNav.select(_nav, TalosNav.PAGES[index])
	_title.text = TABS[index]
	var c: Dictionary = _pages.get(index, {})
	if c.is_empty() or int(c["edits"]) != _edits:
		_status.text = PAGE_NOTES[index] + "   ·   edits apply at once; Ctrl+S saves them"
		_refresh()
		return
	_show_page(index)   # (built and current: just shown - no rebuilding)


## Rebuilds the current page, keeping the scroll positions.
func _refresh() -> void:
	var old: Dictionary = _pages.get(current, {})
	var keep := [_scroll.scroll_vertical, old["inner"].scroll_vertical if not old.is_empty() and is_instance_valid(old["inner"]) else 0]
	if not old.is_empty():
		if is_instance_valid(_sprites) and _sprites.get_parent() == old["box"]:
			old["box"].remove_child(_sprites)   # (kept for next time: _page_graphics)
		old["box"].queue_free()
		old["actions"].queue_free()
	# The page is built into its own box (and its header buttons into theirs).
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = SIZE_EXPAND_FILL
	_content.size_flags_vertical = SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	_body.add_child(_content)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 8)
	_actions_bar.add_child(_actions)
	_inner = null
	match current:
		0: _page_dialogue()
		1: _page_quest()
		2: _page_lore()
		3: _page_interactions()
		4: _page_graphics()
	_pages[current] = {"box": _content, "actions": _actions, "inner": _inner, "status": _status.text, "edits": _edits}
	if not _fonts_scaled:
		_fonts_scaled = true
		UI.scale_fonts(self, "menu", 1.5)
	else:
		UI.scale_fonts(_content, "menu", 1.5)
		UI.scale_fonts(_actions, "menu", 1.5)
	_show_page(current)
	_restore_scroll.call_deferred(keep)


var _fonts_scaled := false

## Shows page `i`'s box and header buttons, hides the others'.
func _show_page(i: int) -> void:
	for k in _pages:
		var on: bool = k == i
		_pages[k]["box"].visible = on
		_pages[k]["actions"].visible = on
	var c: Dictionary = _pages[i]
	_inner = c["inner"]
	_status.text = c["status"]
	# Pages with a list on the left scroll their right side only (the list stays put).
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED if i in [0, 2] else ScrollContainer.SCROLL_MODE_AUTO


func _restore_scroll(v: Array) -> void:
	_scroll.scroll_vertical = v[0]
	if is_instance_valid(_inner):
		_inner.scroll_vertical = v[1]


func _save() -> void:
	dirty = false
	var a := QuestData.save()
	var b := Planets.save_interactions()
	_status.text = ("Saved:  %s   ·   %s" % [a, b]) if a != "" and b != "" else "Save failed - check file permissions."
	

func _reload() -> void:
	dirty = false
	_edits += 1   # (every built page shows the old data: built again when shown)
	QuestData.reload()
	Planets.reload()
	_stage = clampi(_stage, 0, QuestData.STAGES.size() - 1)
	_status.text = "Reloaded from file."
	_refresh()


# --- Small widgets -------------------------------------------------------------------

## Tooltips for the stage fields, by label.
const FIELD_TIPS := {
	"Chapter": "Which chapter of the main quest this stage belongs to (chapter titles: QUEST tab).",
	"Objective": "The objective shown in the HUD and the Ship Computer while this stage is active.",
	"Station": "The station the player must dock at to complete this stage (its exact name).",
	"Position (x, y)": "Where in the system the objective is, in world units (x, y).",
	"Items needed": "Items the player must bring, as id=amount pairs separated by commas, e.g. energy_cell=4, titanium_ore=6.",
	"Enemies": "Ship classes spawned for this stage, separated by commas (ship class ids, e.g. traced_ember).",
	"Reward drachmas": "Drachmas given when the stage is completed (empty or 0: none).",
	"Reward Data Cores": "Data Cores given when the stage is completed (empty or 0: none).",
	"Reward equipment": "An equipment id given when the stage is completed (empty: none).",
	"Unlocks lore ids": "Lore entries unlocked by this stage, as ids separated by commas (ids are shown in the LORE tab).",
	"Title": "The lore entry's title, shown in the lore list.",
}


func _field(label: String, control: Control) -> HBoxContainer:
	var r := HBoxContainer.new()
	r.add_theme_constant_override("separation", 10)
	var l := UI.label(label, 15, UI.TEXT_DIM)
	var tip: String = FIELD_TIPS.get(label, "Chapter title, as shown in the Ship Computer." if label.begins_with("Chapter ") else "")
	if tip != "":
		l.tooltip_text = EditorIcons.tip(label, "", tip)
		l.mouse_filter = MOUSE_FILTER_PASS
		control.tooltip_text = l.tooltip_text
	l.custom_minimum_size.x = 150
	r.add_child(l)
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	r.add_child(control)
	return r


func _line(text: Variant, on_change: Callable) -> LineEdit:
	var e := LineEdit.new()
	e.text = str(text)
	e.text_changed.connect(on_change)
	e.text_changed.connect(func(_t): dirty = true)
	return e


func _text(text: String, on_change: Callable, height := 64.0) -> TextEdit:
	var t := TextEdit.new()
	t.text = text
	t.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	t.custom_minimum_size = Vector2(300, height)
	t.size_flags_horizontal = SIZE_EXPAND_FILL
	t.text_changed.connect(func(): on_change.call(t.text); dirty = true)
	return t


## A small icon button: "Up", "Down", "Delete".
func _small(text: String, cb: Callable, tip := "") -> Button:
	var b := UI.button("", func(): dirty = true; cb.call(), 14)
	b.custom_minimum_size = Vector2(36, 34)
	var icon: String = {"Up": "up", "Down": "down", "Delete": "delete"}.get(text, "")
	if icon == "":
		b.text = text
	EditorIcons.dress(b, icon, EditorIcons.tip(text, "", tip if tip != "" else text))
	return b


# --- Dialogue & stage editor ------------------------------------------------------------

func _page_dialogue() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	_content.add_child(row)
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(360, 0)
	list.size_flags_vertical = SIZE_EXPAND_FILL
	for i in QuestData.STAGES.size():
		var s: Dictionary = QuestData.STAGES[i]
		list.add_item("%2d  %s" % [i, s.get("objective", "")])
	_stage = clampi(_stage, 0, QuestData.STAGES.size() - 1)
	list.select(_stage)
	list.tooltip_text = EditorIcons.tip("Quest stages", "", "Every stage of the main quest in order. Click one to edit it.")
	list.item_selected.connect(func(i): _stage = i; _refresh())
	row.add_child(list)

	_inner = ScrollContainer.new()
	_inner.size_flags_horizontal = SIZE_EXPAND_FILL
	_inner.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(_inner)
	var ed := VBoxContainer.new()
	ed.size_flags_horizontal = SIZE_EXPAND_FILL
	ed.add_theme_constant_override("separation", 6)
	_inner.add_child(ed)
	var s: Dictionary = QuestData.STAGES[_stage]
	ed.add_child(UI.section("STAGE %d   ·   type: %s" % [_stage, s.get("type", "")], ACCENT))

	# The stage's fields, two to a row.
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 6)
	ed.add_child(grid)
	var ch := OptionButton.new()
	for c in QuestData.CHAPTERS:
		ch.add_item(c)
	ch.select(s.get("chapter", 0))
	ch.item_selected.connect(func(i): s["chapter"] = i; dirty = true)
	_cell(grid, "Chapter", ch)
	_cell(grid, "Objective", _line(s.get("objective", ""), func(t): s["objective"] = t))
	if s.has("station"):
		_cell(grid, "Station", _line(s["station"], func(t): s["station"] = t))
	if s.has("pos"):
		var p: Vector2 = s["pos"]
		_cell(grid, "Position (x, y)", _line("%d, %d" % [p.x, p.y], func(t):
			var v: PackedStringArray = str(t).split(",")
			if v.size() == 2 and v[0].strip_edges().is_valid_float() and v[1].strip_edges().is_valid_float():
				s["pos"] = Vector2(float(v[0]), float(v[1]))))
	if s.has("items"):
		var parts := []
		for id in s["items"]:
			parts.append("%s=%d" % [id, s["items"][id]])
		_cell(grid, "Items needed", _line(", ".join(parts), func(t):
			var d := {}
			for kv in str(t).split(",", false):
				var a: PackedStringArray = str(kv).split("=")
				if a.size() == 2 and a[1].strip_edges().is_valid_int():
					d[a[0].strip_edges()] = int(a[1])
			s["items"] = d))
	if s.has("spawn"):
		var parts := []
		for e in s["spawn"]:
			parts.append(e[0])
		_cell(grid, "Enemies", _line(", ".join(parts), func(t):
			var old: Array = s["spawn"]
			var out := []
			var names: PackedStringArray = str(t).split(",", false)
			for i in names.size():
				var id: String = names[i].strip_edges()
				if EnemyTypes.has_type(id):
					var off: Vector2 = old[i][1] if i < old.size() else Vector2.from_angle(i * 1.7) * 350.0
					out.append([id, off])
			s["spawn"] = out))
	var reward: Dictionary = s.get("reward", {})
	_cell(grid, "Reward drachmas", _line(reward.get("credits", 0), func(t): _set_reward(s, "credits", t)))
	_cell(grid, "Reward Data Cores", _line(reward.get("data_core", 0), func(t): _set_reward(s, "data_core", t)))
	_cell(grid, "Reward equipment", _line(reward.get("equipment", ""), func(t): _set_reward(s, "equipment", t)))
	_cell(grid, "Unlocks lore ids", _line(", ".join(s.get("lore", [])), func(t):
		s["lore"] = Array(t.split(",", false)).map(func(x): return x.strip_edges())))

	var lines: Array = s.get("dialogue", [])
	s["dialogue"] = lines
	ed.add_child(UI.section("DIALOGUE  (%d lines, plays when this stage starts)" % lines.size(), ACCENT))
	for k in lines.size():
		var line: Array = lines[k]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 6)
		var sp := _line(line[0], func(t): line[0] = t)
		sp.tooltip_text = EditorIcons.tip("Speaker", "", "Who says the line (shown above it in the dialogue box), e.g. Narrator or a character's name.")
		sp.custom_minimum_size.x = 190
		sp.size_flags_horizontal = SIZE_SHRINK_BEGIN
		sp.size_flags_vertical = SIZE_SHRINK_BEGIN
		r.add_child(sp)
		# (shown formatted as the player sees it; Edit beside it shows the source)
		var tx := RichField.new().setup(line[1], func(t): line[1] = t; dirty = true)
		tx.tooltip_text = EditorIcons.tip("Line", "", "What is said, as the player sees it. Edit (beside it) shows the source: the formatting tags, dimmed -\n[b]bold[/b], [i]italic[/i], [color=gold]colour[/color]; Ctrl+B / Ctrl+I wrap the selected words.")
		r.add_child(tx)
		for b in [_small("Up", func(): _move(lines, k, -1), "Moves this line one place earlier in the stage's dialogue (swaps it with the line above).\nThe dialogue plays top to bottom when the stage starts."),
				_small("Down", func(): _move(lines, k, 1), "Moves this line one place later in the stage's dialogue (swaps it with the line below).\nThe dialogue plays top to bottom when the stage starts."),
				_small("Delete", func(): lines.remove_at(k); _refresh(), "Removes this line from the stage's dialogue. Reload from file (Ctrl+R) brings back everything\nsince the last save if you delete something by mistake.")]:
			b.size_flags_vertical = SIZE_SHRINK_BEGIN
			r.add_child(b)
		ed.add_child(r)
	var add := EditorIcons.dress(UI.button("Add line", func():
		dirty = true
		lines.append([lines[-1][0] if not lines.is_empty() else "Narrator", "..."])
		_refresh(), 15), "add", EditorIcons.tip("Add line", "", "Adds a new line at the end of this stage's dialogue, with the same speaker as the last line\n(or Narrator) and '...' as its text. Edit it, then move it with the arrows if it belongs earlier."))
	add.size_flags_horizontal = SIZE_SHRINK_BEGIN
	ed.add_child(add)
	var prev := EditorIcons.dress(UI.button("Preview dialogue", func(): _preview(lines), 16), "play",
		EditorIcons.tip("Preview dialogue", "Ctrl+P", "Plays this stage's dialogue in the game's own dialogue box, as the player will see it.\nClick, Space or Enter to advance a line; Skip ends it and returns here."))
	prev.disabled = dialogue == null
	_actions.add_child(prev)


## A label and its field in a grid of label / field pairs.
func _cell(grid: GridContainer, label: String, control: Control) -> void:
	var f := _field(label, control)
	for c in f.get_children():
		f.remove_child(c)
		grid.add_child(c)
	f.free()


func _set_reward(s: Dictionary, key: String, t: String) -> void:
	if not s.has("reward"):
		s["reward"] = {}
	var r: Dictionary = s["reward"]
	if key == "equipment":
		if t.strip_edges() == "":
			r.erase(key)
		else:
			r[key] = t.strip_edges()
	elif t.strip_edges().is_valid_int() and int(t) > 0:
		r[key] = int(t)
	else:
		r.erase(key)


func _move(lines: Array, k: int, d: int) -> void:
	var j := k + d
	if j < 0 or j >= lines.size():
		return
	var tmp: Variant = lines[k]
	lines[k] = lines[j]
	lines[j] = tmp
	dirty = true
	_refresh()


func _preview(lines: Array) -> void:
	if dialogue == null or lines.is_empty():
		return
	hide()
	dialogue.play(lines.duplicate(true), func(): show(), true)


# --- Quest control ---------------------------------------------------------------------

func _page_quest() -> void:
	_content.add_child(UI.section("CHAPTER TITLES", ACCENT))
	for i in QuestData.CHAPTERS.size():
		_content.add_child(_field("Chapter %d" % i, _line(QuestData.CHAPTERS[i], func(t): QuestData.CHAPTERS[i] = t)))


# --- Lore ------------------------------------------------------------------------------

func _page_lore() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_content.add_child(row)
	row.size_flags_vertical = SIZE_EXPAND_FILL
	var list := ItemList.new()
	list.custom_minimum_size = Vector2(320, 0)
	list.size_flags_vertical = SIZE_EXPAND_FILL
	var ids: Array = QuestData.LORE.keys()
	if _lore_id == "" or not QuestData.LORE.has(_lore_id):
		_lore_id = ids[0] if not ids.is_empty() else ""
	for id in ids:
		list.add_item(QuestData.LORE[id]["title"])
		if id == _lore_id:
			list.select(list.item_count - 1)
	list.tooltip_text = EditorIcons.tip("Lore entries", "", "The lore the player can unlock. Click one to edit its title and text.")
	list.item_selected.connect(func(i): _lore_id = ids[i]; _refresh())
	row.add_child(list)
	if _lore_id == "":
		return
	var e: Dictionary = QuestData.LORE[_lore_id]
	var ed := VBoxContainer.new()
	ed.size_flags_horizontal = SIZE_EXPAND_FILL
	ed.add_theme_constant_override("separation", 8)
	ed.add_child(UI.section("LORE ENTRY  ·  id: %s" % _lore_id, ACCENT))
	ed.add_child(_field("Title", _line(e["title"], func(t): e["title"] = t)))
	ed.add_child(UI.label("Text, as the player reads it - Edit to change it (Ctrl+B bold, Ctrl+I italic)", 14, UI.TEXT_DIM))
	var lt := RichField.new().setup(e["text"], func(t): e["text"] = t; dirty = true, 200.0, true)
	lt.tooltip_text = EditorIcons.tip("Lore text", "", "The entry's text, shown as the player reads it. Edit (beside it) shows the source:\nthe formatting tags, dimmed - [b]bold[/b], [i]italic[/i]; Ctrl+B / Ctrl+I wrap the selected words.")
	ed.add_child(lt)
	row.add_child(ed)


# --- Interactions ------------------------------------------------------------------------

func _page_interactions() -> void:
	_content.add_child(UI.section("MINOAN CITIZEN LINES  (Minoan words  ·  translation shown in the event log)", ACCENT))
	for k in Planets.NPC_LINES.size():
		var line: Array = Planets.NPC_LINES[k]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 8)
		var a := _line(line[0], func(t): line[0] = t)
		a.tooltip_text = EditorIcons.tip("Minoan words", "", "What the citizen says (shown in their speech bubble).")
		a.size_flags_horizontal = SIZE_EXPAND_FILL
		r.add_child(a)
		var b := _line(line[1], func(t): line[1] = t)
		b.tooltip_text = EditorIcons.tip("Translation", "", "The meaning, shown in the event log when they say it.")
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		r.add_child(b)
		r.add_child(_small("Delete", func(): Planets.NPC_LINES.remove_at(k); _refresh(), "Removes this line: citizens won't say it any more. Reload from file (Ctrl+R) brings back\neverything since the last save if you delete something by mistake."))
		_content.add_child(r)
	var add := (EditorIcons.dress(UI.button("Add citizen line", func(): dirty = true; Planets.NPC_LINES.append(["...", "..."]); _refresh(), 15), "add",
		EditorIcons.tip("Add citizen line", "", "Adds a new line Minoan citizens can say, with '...' to fill in: the Minoan words on the left\n(shown in their speech bubble) and the translation on the right (shown in the event log).\nA random line is picked every time the player clicks a citizen.")))
	add.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_content.add_child(add)


# --- Player ---------------------------------------------------------------------------------

## Every sprite (data/sprites, cut from the reference sheets in external/images/ by
## tools/extract_sprites.py), as thumbnails by group.
func _page_graphics() -> void:
	_status.text = "data/sprites - re-run tools/extract_sprites.py after changing external/images/, then reload them here"
	_actions.add_child(EditorIcons.dress(UI.button("Reload sprites", func():
		await ProcArt.rebake()
		_status.text = "Sprites reloaded."
		if is_instance_valid(_sprites):
			_sprites.queue_free()
		_sprites = null
		_refresh(), 15), "bake", EditorIcons.tip("Reload sprites", "", "Reads every sprite in data/sprites again and rebuilds the Minoan building textures - after you\nre-run tools/extract_sprites.py on changed reference sheets in external/images/. Takes a few seconds.")))
	# (built once - some 700 thumbnails - and kept while you visit other pages)
	if is_instance_valid(_sprites):
		_content.add_child(_sprites)
		return
	_sprites = VBoxContainer.new()
	_sprites.add_theme_constant_override("separation", 10)
	_content.add_child(_sprites)
	var groups := {}
	for j in ProcArt.bake_jobs():
		var g: String = str(j[2]).get_slice(":", 0)
		if not groups.has(g):
			groups[g] = []
		groups[g].append(j)
	for g in groups:
		_sprites.add_child(UI.section("%s  (%d)" % [g.to_upper(), groups[g].size()], ACCENT))
		var grid := HFlowContainer.new()
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 6)
		_sprites.add_child(grid)
		for j in groups[g]:
			var tr := TextureRect.new()
			tr.texture = ProcArt.get_tex(j[0])
			tr.custom_minimum_size = Vector2(72, 72)
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.tooltip_text = EditorIcons.tip(str(j[0]), "", "%s\n%d x %d px" % [j[1], tr.texture.get_width() if tr.texture else 0, tr.texture.get_height() if tr.texture else 0])
			grid.add_child(tr)
