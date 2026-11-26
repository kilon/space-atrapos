class_name RichField
extends VBoxContainer
## A text field for BBCode text (lore, dialogue): it shows the text as the
## player sees it - bold, italic, colours - with an Edit button beside it;
## Edit shows the source, the tags dimmed so the words stand out, with B / I
## buttons (Ctrl+B / Ctrl+I) that wrap the selection. Done (or Esc, or a
## click elsewhere) shows the formatted text again.
##   var f := RichField.new(); f.setup(text, func(t): ..., 200.0, true)

signal changed(text: String)

var text := ""
var on_change := Callable()
var _view: RichTextLabel
var _edit: TextEdit
var _tools: VBoxContainer          # (the B / I buttons, while editing)
var _edit_btn: Button              # Edit / Done
var _expand := false
const TAG := Color(0.55, 0.5, 0.42, 0.75)        # (the tags while editing: dim)
const PLACEHOLDER := "[color=#7a6a55][i]Empty - press Edit to write. [b]Bold[/b] and [i]italic[/i] with Ctrl+B / Ctrl+I.[/i][/color]"


## `height`: the least height; `expand`: fill the space it's given (the lore
## page) rather than fit its text (dialogue lines).
func setup(t: String, cb: Callable, height := 0.0, expand := false) -> RichField:
	text = t
	on_change = cb
	_expand = expand
	add_theme_constant_override("separation", 2)
	size_flags_horizontal = SIZE_EXPAND_FILL
	if expand:
		size_flags_vertical = SIZE_EXPAND_FILL
	# The text (formatted, or its source) and beside it its buttons: Edit /
	# Done, and while editing B / I. (None of them takes the focus: the
	# selection stays.)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = SIZE_EXPAND_FILL
	if expand:
		row.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(row)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = SIZE_EXPAND_FILL
	if expand:
		body.size_flags_vertical = SIZE_EXPAND_FILL
	row.add_child(body)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 4)
	side.size_flags_vertical = SIZE_SHRINK_BEGIN
	row.add_child(side)
	_edit_btn = Button.new()
	_edit_btn.focus_mode = Control.FOCUS_NONE
	_edit_btn.custom_minimum_size = Vector2(92, 32)
	_edit_btn.pressed.connect(func(): _show_view() if editing() else _show_edit())
	side.add_child(_edit_btn)
	_tools = VBoxContainer.new()
	_tools.add_theme_constant_override("separation", 4)
	_tools.visible = false
	for spec in [["B", "b", "Bold (Ctrl+B): wraps the selected words in [b]...[/b]."], ["I", "i", "Italic (Ctrl+I): wraps the selected words in [i]...[/i]."]]:
		var b := Button.new()
		b.text = spec[0]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(92, 28)
		b.tooltip_text = spec[2]
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(_wrap.bind(spec[1]))
		_tools.add_child(b)
	side.add_child(_tools)
	_dress_button()

	_edit = TextEdit.new()
	_edit.text = t
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.custom_minimum_size = Vector2(300, height)
	_edit.size_flags_horizontal = SIZE_EXPAND_FILL
	if expand:
		_edit.size_flags_vertical = SIZE_EXPAND_FILL
	else:
		_edit.scroll_fit_content_height = true
	_edit.syntax_highlighter = tag_highlighter()
	_edit.visible = false
	_edit.text_changed.connect(func():
		text = _edit.text
		if on_change.is_valid():
			on_change.call(text)
		changed.emit(text))
	_edit.focus_exited.connect(_show_view)
	_edit.gui_input.connect(_edit_keys)
	body.add_child(_edit)

	_view = RichTextLabel.new()
	_view.bbcode_enabled = true
	_view.selection_enabled = false
	_view.custom_minimum_size = Vector2(300, maxf(height, 34.0))
	_view.size_flags_horizontal = SIZE_EXPAND_FILL
	if expand:
		_view.size_flags_vertical = SIZE_EXPAND_FILL
	else:
		_view.fit_content = true
		_view.scroll_active = false
	body.add_child(_view)
	_style_view.call_deferred()
	_render()
	return self


## The formatted view in the look of a text box (so it reads as a field).
func _style_view() -> void:
	if not is_instance_valid(_view):
		return
	var sb := _edit.get_theme_stylebox("normal")
	if sb:
		_view.add_theme_stylebox_override("normal", sb)
		_view.add_theme_stylebox_override("focus", sb)
	var fs := _edit.get_theme_font_size("font_size")
	if fs > 0:
		for k in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
			_view.add_theme_font_size_override(k, fs)
	_view.add_theme_color_override("default_color", _edit.get_theme_color("font_color"))


## A highlighter for BBCode source: the tags dimmed, the words as they are.
static func tag_highlighter() -> CodeHighlighter:
	var hl := CodeHighlighter.new()
	hl.add_color_region("[", "]", TAG)
	hl.number_color = Color.WHITE   # (numbers as the rest of the text)
	hl.symbol_color = Color.WHITE
	hl.function_color = Color.WHITE
	hl.member_variable_color = Color.WHITE
	return hl


## The Edit / Done button's look for the mode.
func _dress_button() -> void:
	if editing():
		EditorIcons.dress(_edit_btn, "accept", EditorIcons.tip("Done", "Esc", "Shows the text formatted again, as the player will read it."), "Done")
	else:
		EditorIcons.dress(_edit_btn, "pencil", EditorIcons.tip("Edit", "", "Shows the text's source to change it: the formatting tags show, dimmed -\n[b]bold[/b], [i]italic[/i], [color=gold]colour[/color]; Ctrl+B / Ctrl+I (or B / I) wrap the selected words."), "Edit")


func _render() -> void:
	_view.text = text if text.strip_edges() != "" else PLACEHOLDER


func _show_edit() -> void:
	_edit.text = text
	_view.visible = false
	_edit.visible = true
	_tools.visible = true
	_dress_button()
	_edit.grab_focus()
	_edit.set_caret_line(_edit.get_line_count() - 1)
	_edit.set_caret_column(_edit.get_line(_edit.get_line_count() - 1).length())


func _show_view() -> void:
	_render()
	_edit.visible = false
	_tools.visible = false
	_view.visible = true
	_dress_button()


## Whether the source is showing (being edited).
func editing() -> bool:
	return _edit != null and _edit.visible


func _edit_keys(ev: InputEvent) -> void:
	if not ev is InputEventKey or not ev.pressed:
		return
	var k := ev as InputEventKey
	if k.keycode == KEY_ESCAPE:
		_edit.release_focus()   # (done: the formatted text - not Talos's Esc)
		_edit.accept_event()
	elif k.ctrl_pressed and k.keycode == KEY_B:
		_wrap("b")
		_edit.accept_event()
	elif k.ctrl_pressed and k.keycode == KEY_I:
		_wrap("i")
		_edit.accept_event()


## Wraps the selection in [tag]...[/tag] (no selection: the tags, the caret
## between them).
func _wrap(tag: String) -> void:
	var open := "[%s]" % tag
	var close := "[/%s]" % tag
	if _edit.has_selection():
		var sel := _edit.get_selected_text()
		_edit.delete_selection()
		_edit.insert_text_at_caret(open + sel + close)
	else:
		_edit.insert_text_at_caret(open + close)
		_edit.set_caret_column(_edit.get_caret_column() - close.length())
	_edit.grab_focus()
