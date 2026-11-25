extends HBoxContainer
## Automaton tab: the main quest log - chapter list, current objective
## and a journal of every story conversation so far.

const GOLD := Color(1.0, 0.82, 0.38)

var data: Node
var ship: Node2D

var _chapters: VBoxContainer
var _title: Label
var _objective: Label
var _journal: RichTextLabel


func _ready() -> void:
	add_theme_constant_override("separation", 30)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(330, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	left.add_child(UI.section("THE THREAD OF ARIADNE", GOLD))
	_chapters = VBoxContainer.new()
	_chapters.add_theme_constant_override("separation", 6)
	left.add_child(_chapters)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	_title = UI.label("", 24, GOLD)
	right.add_child(_title)
	_objective = UI.label("", 17, Color.WHITE)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_objective)
	right.add_child(UI.section("JOURNAL"))
	_journal = RichTextLabel.new()
	_journal.bbcode_enabled = true
	_journal.scroll_following = true
	_journal.custom_minimum_size = Vector2(780, 470)
	_journal.add_theme_font_size_override("normal_font_size", 15)
	_journal.add_theme_font_size_override("bold_font_size", 15)
	_journal.add_theme_font_size_override("italics_font_size", 15)
	right.add_child(_journal)


func refresh() -> void:
	var quest := get_tree().get_first_node_in_group("quest")
	if quest == null or quest.stage < 0:
		_title.text = "The story hasn't started yet."
		return
	var current_chapter: int = quest.current().get("chapter", 0)

	UI.clear(_chapters)
	for i in QuestData.CHAPTERS.size():
		var done: bool = i < current_chapter or quest.finished
		var col := Color(0.5, 0.9, 0.55) if done else (GOLD if i == current_chapter else Color(0.45, 0.47, 0.52))
		var mark := "[done]  " if done else ("  >>  " if i == current_chapter else "        ")
		var text: String = QuestData.CHAPTERS[i] if i <= current_chapter or quest.finished else "? ? ?"
		_chapters.add_child(UI.label(mark + text, 16, col))

	_title.text = quest.chapter_title()
	_objective.text = ("Objective: " if not quest.finished else "") + quest.objective_text()

	var lines := []
	var last_chapter := -1
	for entry in quest.journal():
		var s: Dictionary = entry[1]
		if s["chapter"] != last_chapter:
			last_chapter = s["chapter"]
			lines.append("\n[color=#ffd166][b]%s[/b][/color]" % QuestData.CHAPTERS[last_chapter])
		for line in s.get("dialogue", []):
			lines.append("[color=#ffd166]%s:[/color] %s" % [line[0], line[1]])
	_journal.text = "\n".join(lines).strip_edges()
