extends Control
## Story dialogue box for the main quest. Shows lines one at a time
## ([speaker, bbcode text]); click, Space or Enter to continue, or Skip.
## Esc opens the Esc menu on top (it never closes the dialogue).
## Pauses the game while open, and works on top of other paused panels
## (it only unpauses if it was the one that paused).
## Speakers with a picture in PORTRAITS are shown beside their lines.

signal finished

const GOLD := Color(1.0, 0.82, 0.38)
## Speaker -> portrait (shown left of the text while they speak).
const PORTRAITS := {"Kilon Alios": "res://art/kilon/kilon_portrait.png"}
const TEXT_WIDTH := 1100.0
const PORTRAIT_SIZE := 150.0

var _lines: Array = []
var _index := 0
var _paused_by_me := false
var _on_done: Callable

var _speaker: Label
var _portrait: TextureRect
var _portrait_box: PanelContainer
var _text: RichTextLabel
var _counter: Label
var _next: Button
var _exit: Button                  # preview only: leave the preview
var _banner: Label                 # preview only
## Previewing (the editor): an exit button and banner, and Esc exits.
var preview := false


func _ready() -> void:
	add_to_group("dialogue_boxes")
	hide()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_build()
	UI.scale_fonts(self, "dialogue")
	Settings.text_scale_changed.connect(func(): UI.scale_fonts(self, "dialogue"))


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(NeonTheme.BG, 0.45)
	dim.set_anchors_preset(PRESET_FULL_RECT)
	dim.gui_input.connect(_on_click)
	add_child(dim)

	var panel := PanelContainer.new()
	var style := UI.panel_style(GOLD.darkened(0.2))
	style.bg_color = Color(0.05, 0.04, 0.06, 0.97)
	panel.add_theme_stylebox_override("panel", style)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -600
	panel.offset_right = 600
	panel.offset_top = -360
	panel.offset_bottom = -130
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN  # bigger text grows it upward
	panel.gui_input.connect(_on_click)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	margin.add_theme_constant_override("margin_top", 6)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	v.add_child(Meander.new())

	# The speaker's portrait (if they have one) beside their name and line.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	v.add_child(row)
	_portrait_box = PanelContainer.new()
	var frame := UI.panel_style(GOLD.darkened(0.25))
	frame.bg_color = Color(0.1, 0.08, 0.07)
	_portrait_box.add_theme_stylebox_override("panel", frame)
	_portrait_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_portrait_box.mouse_filter = MOUSE_FILTER_IGNORE
	_portrait_box.visible = false
	row.add_child(_portrait_box)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = MOUSE_FILTER_IGNORE
	_portrait_box.add_child(_portrait)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 8)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	_speaker = UI.label("", 22, GOLD)
	words.add_child(_speaker)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.custom_minimum_size = Vector2(TEXT_WIDTH, 90)
	_text.mouse_filter = MOUSE_FILTER_IGNORE
	_text.add_theme_font_size_override("normal_font_size", 19)
	_text.add_theme_font_size_override("bold_font_size", 19)
	_text.add_theme_font_size_override("italics_font_size", 19)
	_text.add_theme_color_override("default_color", Color(0.93, 0.9, 0.84))
	words.add_child(_text)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	_banner = UI.label("PREVIEW", 14, NeonTheme.HEAD)
	_banner.visible = false
	footer.add_child(_banner)
	footer.add_child(UI.label("Click, Space or Enter to continue", 13, UI.TEXT_DIM))
	footer.add_child(UI.spacer())
	_counter = UI.label("", 14, UI.TEXT_DIM)
	footer.add_child(_counter)
	var skip := EditorIcons.dress(UI.button("", _finish, 14), "skip", EditorIcons.tip("Skip", "", "Ends the conversation now, skipping the remaining lines. The story goes on as if you'd read them\n(the quest journal keeps the text)."))
	skip.focus_mode = FOCUS_NONE
	footer.add_child(skip)
	_next = EditorIcons.dress(UI.button("", advance, 16), "next", EditorIcons.tip("Continue", "Space  ·  Enter  ·  click", "Shows the next line of the conversation (the last line closes it)."))
	_next.focus_mode = FOCUS_NONE
	footer.add_child(_next)
	_exit = EditorIcons.dress(UI.button("", _finish, 16), "exit", EditorIcons.tip("Exit preview", "Esc", "Stops the preview and returns to the editor.\nNothing changes in the quest - a preview only shows the lines as the player would see them."))
	_exit.focus_mode = FOCUS_NONE
	_exit.visible = false
	footer.add_child(_exit)
	v.add_child(footer)


## Show `lines` ([speaker, text] pairs); `on_done` runs after the last one.
func play(lines: Array, on_done := Callable(), as_preview := false) -> void:
	preview = as_preview
	_exit.visible = as_preview
	_banner.visible = as_preview
	if lines.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_lines = lines
	_index = 0
	_on_done = on_done
	_paused_by_me = not get_tree().paused
	get_tree().paused = true
	# A conversation never keeps the mouse: if it opened while you were holding
	# the button to steer (the cursor hidden), the release would land here and
	# the cursor would stay hidden - so steering ends and the cursor shows.
	get_tree().call_group("steering", "release_steering")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)
	show()
	_show_line()


## The portrait of a speaker (null if they have none).
static func portrait_for(speaker: String) -> Texture2D:
	var path: String = PORTRAITS.get(speaker, "")
	return load(path) if path != "" and ResourceLoader.exists(path) else null


func is_open() -> bool:
	return visible


func advance() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish()
	else:
		_show_line()


func _show_line() -> void:
	var line: Array = _lines[_index]
	_speaker.text = line[0]
	_text.text = line[1]
	Voice.speak(line[1], line[0])   # (its recording, in the speaker's voice)
	var pic := portrait_for(line[0])
	_portrait.texture = pic
	_portrait_box.visible = pic != null
	_text.custom_minimum_size.x = TEXT_WIDTH - (PORTRAIT_SIZE + 30.0 if pic else 0.0)
	_counter.text = "%d / %d" % [_index + 1, _lines.size()]
	var last := _index >= _lines.size() - 1
	_next.icon = EditorIcons.get_icon("close" if last else "next")
	_next.tooltip_text = EditorIcons.tip("Close" if last else "Continue", "Space  ·  Enter  ·  click",
		"Closes the conversation (this is its last line)." if last else "Shows the next line of the conversation (the last line closes it).")
	_next.set_meta("tip", "")


func _finish() -> void:
	hide()
	Voice.stop()
	if _paused_by_me:
		get_tree().paused = false
	var cb := _on_done
	_on_done = Callable()
	finished.emit()
	if cb.is_valid():
		cb.call()


func _on_click(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()


# _input so it wins over other open panels (station menu etc.).
func _input(event: InputEvent) -> void:
	if not visible or UI.esc_menu_open():
		return  # the Esc menu on top handles input
	if event.is_action_pressed("ui_cancel"):
		if preview:
			_finish()   # Esc leaves a preview
		else:
			UI.open_esc_menu()
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		advance()
	elif event is InputEventKey:
		pass  # swallow other keys while talking
	else:
		return
	get_viewport().set_input_as_handled()


## Greek key (meander) band, drawn along the top of the dialogue box.
class Meander extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(0, 18)
		mouse_filter = MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var col := Color(1.0, 0.82, 0.38, 0.75)
		var u := 6.0   # unit size
		var x := 0.0
		var y0 := 2.0
		while x + u * 4 <= size.x:
			# One meander unit: a squared spiral hook.
			var pts := PackedVector2Array([
				Vector2(x, y0 + u * 2), Vector2(x, y0), Vector2(x + u * 3, y0),
				Vector2(x + u * 3, y0 + u * 2), Vector2(x + u, y0 + u * 2),
				Vector2(x + u, y0 + u), Vector2(x + u * 2, y0 + u)])
			draw_polyline(pts, col, 1.6)
			draw_line(Vector2(x, y0 + u * 2), Vector2(x + u * 4, y0 + u * 2), col, 1.6)
			x += u * 4
