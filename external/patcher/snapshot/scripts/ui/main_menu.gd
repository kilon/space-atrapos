extends Control
## Main menu. Also used in-game as the pause menu (overlay = true): the game
## stays loaded and paused underneath, and "Start Game" becomes "Resume".

const GAME_SCENE := "res://scenes/world/cosmos.tscn"
const EDITOR_SCENE := "res://scenes/editor/editor.tscn"
const LATER_SCENES := ["res://scenes/world/cosmos.tscn", "res://scenes/ui/station_menu.tscn", "res://scenes/ui/ship_menu.tscn"]

## True when this menu is shown on top of a paused game.
@export var overlay := false

@onready var main_buttons: Control = %MainButtons
@onready var settings_panel: Control = %SettingsPanel
@onready var resolution_option: OptionButton = %ResolutionOption
@onready var fullscreen_check: CheckButton = %FullscreenCheck

## Text-size sliders: category -> [HSlider, value Label, reset Button] (built in code).
## Volume sliders: "master" / "music" / "sfx" -> [HSlider, value Label, reset Button].
var _volume_sliders := {}
var _text_sliders := {}
var _settings_hint: Label
## The CRT filter: its own settings page (built in code), its switch on the
## main settings page, and its sliders: id -> [HSlider, value Label, reset Button].
var crt_panel: PanelContainer
var _crt_check: CheckButton
var _fps_check: CheckButton
var _graphics_pick: OptionButton
var _terrain_check: CheckButton
var _aa_pick: OptionButton
var _crt_switches := {}
var _crt_sliders := {}

var _resolutions: Array[Vector2i] = []
var _was_paused := false


func _ready() -> void:
	Mods.started()   # (the title screen reached: this start's mods are fine)
	if get_tree().current_scene == self and "--mod-editor" in OS.get_cmdline_user_args() and not Engine.has_meta("mod_editor_opened"):
		Engine.set_meta("mod_editor_opened", true)   # (once: Back from it comes here)
		get_tree().change_scene_to_file.call_deferred("res://scenes/editor/mod_editor.tscn")
	if get_tree().current_scene == self:
		NeonTheme.set_empire("")   # title screen: the neutral neon look
	%StartButton.pressed.connect(_on_start)
	%SaveButton.pressed.connect(_on_save)
	%LoadButton.pressed.connect(_on_load)
	%SettingsButton.pressed.connect(_open_settings)
	%QuitToMenuButton.pressed.connect(_on_quit_to_menu)
	%ExitButton.pressed.connect(get_tree().quit)
	if Settings.on_web():
		%ExitButton.visible = false   # (a browser tab: closed by the browser, not the game)
		resolution_option.get_parent().visible = false   # (the Resolution row: the page sets the size)
	%BackButton.pressed.connect(_close_settings)
	resolution_option.item_selected.connect(_on_resolution_selected)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	%StartButton.tooltip_text = "Back to your game, where you left it." if overlay else "A new game: a new galaxy charted, and you on foot on Amnissos with no ship yet."
	%SaveButton.tooltip_text = "Saves your game into one of the slots (pick it on the next page). F5 quicksaves at any time."
	%LoadButton.tooltip_text = "Pick a save to load: the quicksave, the autosave or a numbered slot."
	%SettingsButton.tooltip_text = "Display, text size, sound, controls (keys and gamepad) and game options."
	%QuitToMenuButton.tooltip_text = "Leaves this game for the title screen (unsaved progress since your last save is lost)."
	%ExitButton.tooltip_text = "Closes the game (unsaved progress since your last save is lost)."
	%BackButton.tooltip_text = "Back to the menu (the settings are already kept)."
	resolution_option.tooltip_text = "Windowed: the window's size in pixels. Fullscreen: the resolution the world is drawn at, scaled up to fill the screen (lower: faster; the menus stay sharp)."
	fullscreen_check.tooltip_text = "Fills the whole screen, the world drawn at the resolution above. Off: a window of that size."
	# Pause-only buttons.
	%SaveButton.visible = overlay
	%QuitToMenuButton.visible = overlay
	# Talos, the game's editor (game data, sprites, the asset Library...): from
	# the title screen; in a game (the Esc menu, or F8) it saves the game first
	# and leaving Talos brings you back to it (SaveGame.open_talos).
	var fs: int = %SettingsButton.get_theme_font_size("font_size")
	var editor := Button.new()
	editor.name = "EditorButton"
	editor.text = "Talos"
	editor.tooltip_text = "The game's editor. Leaving it brings you back here." if overlay else "The game's editor: quests, lore, citizens, sprites, meshes, animation."
	if overlay:
		editor.pressed.connect(func(): SaveGame.open_talos())
	else:
		editor.pressed.connect(_open_talos_when_ready)
	editor.add_theme_font_size_override("font_size", fs)
	main_buttons.add_child(editor)
	main_buttons.move_child(editor, %SettingsButton.get_index() + 1)
	# The Archive: every book of the game (the guide, tutorial, encyclopedia, controls, versions, Talos manual).
	var books := Button.new()
	books.name = "ArchiveButton"
	books.text = "Archive"
	books.tooltip_text = "Every book of the game in one place: the pilot's guide, the tutorial, the encyclopedia, the controls, the versions and the Talos manual (F1 anywhere)."
	books.pressed.connect(func(): Archive.open(self, "guide"))
	books.add_theme_font_size_override("font_size", fs)
	main_buttons.add_child(books)
	main_buttons.move_child(books, editor.get_index() + 1)
	# Patch Notes: every version of the game and its patches (over this menu - the game, if any, stays paused under it).
	var notes := Button.new()
	notes.name = "PatchNotesButton"
	notes.text = "Patch Notes"
	notes.tooltip_text = "Every version of the game and its patches: what each brought, step by step, with the code behind it."
	notes.pressed.connect(func(): load("res://scripts/editor/patcher.gd").open_over(self))
	notes.add_theme_font_size_override("font_size", fs)
	main_buttons.add_child(notes)
	main_buttons.move_child(notes, books.get_index() + 1)
	# Mods: turn them on and off, their order, the Mod Editor (the title screen only - mods load as the game starts).
	if not overlay:
		var mods := Button.new()
		mods.name = "ModsButton"
		mods.text = "Mods"
		mods.tooltip_text = "Your mods: turn them on and off, set their order, install them, make your own in the Mod Editor."
		mods.pressed.connect(func(): load("res://scripts/ui/mods_screen.gd").open_over(self))
		mods.add_theme_font_size_override("font_size", fs)
		main_buttons.add_child(mods)
		main_buttons.move_child(mods, notes.get_index() + 1)
	# Title screen: Continue - straight into the latest save (shown when there is one).
	if not overlay:
		var cont := Button.new()
		cont.name = "ContinueButton"
		cont.text = "Continue"
		cont.pressed.connect(func(): SaveGame.load_slot(-1))
		cont.add_theme_font_size_override("font_size", fs)
		main_buttons.add_child(cont)
		main_buttons.move_child(cont, %StartButton.get_index())

	if not overlay:
		Galaxy.active = false   # no game running behind the title screen
		_warm_talos.call_deferred()
	if overlay:
		add_to_group("esc_menu")
		%StartButton.text = "Resume"
		$Background.hide()  # let the paused game show through instead
		$Dim.show()

	_apply_look()
	if not overlay:
		_refresh_load_button()   # (the Esc menu: when it opens - open())
		# The title screen: the game's first-use drawing (shaders, a station's
		# labels, particles) done here, one thing a frame, unseen - not in the
		# first frame of a new game (Warmup: once a run).
		_start_warmup()   # (the GPU's first-use work, at the title)
		ProcArt.load_scenes(LATER_SCENES)   # (the game's scenes, behind the menu - no loading screen)

	_resolutions = Settings.available_resolutions()
	for r in _resolutions:
		resolution_option.add_item("%d × %d" % [r.x, r.y])

	Keybinds.register_menu(self)   # (WASD / D-pad move between the buttons)
	Settings.text_scale_changed.connect(_apply_text_size)
	# The Esc menu in a game: its settings pages built (and its text sized)
	# the first time it opens, not with every scene - a jump, a landing.
	if overlay:
		_lazy = true
		settings_panel.hide()
	else:
		_build_settings()


var _lazy := false

func _build_settings() -> void:
	_lazy = false
	_build_text_settings()
	_build_crt_settings()
	_tabify_settings()
	_apply_text_size()
	_close_settings()


## 80s look: chrome title, synthwave backdrop (title screen), slanted neon
## buttons and a neon settings panel.
func _apply_look() -> void:
	if not overlay:
		var sw := Synthwave.new()
		$Background.add_child(sw)
	var old: Control = $Center/Layout/Title
	var title := RetroTitle.new()
	if overlay:
		title.big_size = 96
		title.small_size = 30
	old.get_parent().add_child(title)
	old.get_parent().move_child(title, old.get_index())
	old.queue_free()
	$Center/Layout.add_theme_constant_override("separation", 26 if not overlay else 22)
	var styles := NeonTheme.menu_button_styles()
	for b in main_buttons.get_children():
		if b is Button:
			for k in styles:
				b.add_theme_stylebox_override(k, styles[k])
			b.add_theme_font_override("font", NeonTheme.heavy_font())
			b.text = b.text.to_upper()
			b.custom_minimum_size = Vector2(380, 54)
	main_buttons.add_theme_constant_override("separation", 14)
	settings_panel.add_theme_stylebox_override("panel", NeonTheme.box(Color(NeonTheme.CYAN, 0.75), NeonTheme.BG, 2, 12, 14))
	%StatusLabel.add_theme_color_override("font_color", NeonTheme.PINK)
	var heading: Label = settings_panel.get_node("Margin/Rows/Heading")
	heading.text = heading.text.to_upper()
	heading.add_theme_font_override("font", NeonTheme.heavy_font())
	heading.add_theme_color_override("font_color", NeonTheme.HEAD)


## Pause the game and show this menu (overlay mode). It can open on top of
## other paused panels (dialogue, Automaton, station); resuming returns
## to them still paused.
func open() -> void:
	if _lazy:
		_build_settings()
	if not visible:   # (already open: it keeps what it'll go back to)
		_was_paused = get_tree().paused
	get_tree().paused = true
	show()
	_refresh_load_button()
	_close_settings()


## Hide this menu and go back to whatever was open (overlay mode).
func resume() -> void:
	hide()
	Settings.crt_preview = false
	get_tree().paused = _was_paused


## The game's first-use drawing (Warmup), on the title screen.
func _start_warmup() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if not CosmosWarm.done:
		add_child(CosmosWarm.new())   # (the 3D game's: its shaders, noise, spheres)


func _exit_tree() -> void:
	Settings.crt_preview = false


## Attract mode: the title screen left alone for AttractMode.IDLE seconds
## starts the game playing itself (any input meanwhile restarts the count).
var _idle := 0.0

func _process(delta: float) -> void:
	if overlay or not visible or get_tree().current_scene != self:
		_idle = 0.0
		return
	_idle += delta   # (the old game's attract mode is gone)


func _input(event: InputEvent) -> void:
	if _listen_id != "" and _listen(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton \
			or (event is InputEventMouseMotion and event.relative.length() > 1.0):
		_idle = 0.0


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_action_pressed("ui_cancel"):
		return
	if SaveGame.talos_overlay() != null or SaveGame.talos_closed_frame == Engine.get_process_frames():
		return   # (Talos over the game has the keys - this Esc was for it, the menu waits under it)
	if crt_panel.visible:
		_close_crt()
	elif _slots_panel and _slots_panel.visible:
		_close_slots()
	elif settings_panel.visible:
		_close_settings()
	elif overlay:
		resume()
	get_viewport().set_input_as_handled()


## Talos's scripts and scenes loaded in the background a few seconds after the title shows (its mesh
## editor - what Talos opens on - is thousands of lines: ~0.4 s compiled in the foreground), so the
## first click on Talos finds them ready. Not in a browser (loading scripts on threads there stalls).
func _warm_talos() -> void:
	if Settings.on_web() or DisplayServer.get_name() == "headless":
		return
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	for path in [EDITOR_SCENE, "res://scenes/editor/mesh_editor.tscn"]:
		if not ResourceLoader.has_cached(path) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			ResourceLoader.load_threaded_request(path, "", true)


## Talos from the title screen - once the game's art is in (it shows all of it).
func _open_talos_when_ready() -> void:
	# (at once: the art goes on loading behind it)
	get_tree().change_scene_to_packed(TalosNav.scene(EDITOR_SCENE))   # (the one loaded in the background, if it's in)


func _on_start() -> void:
	if overlay:
		resume()
	else:
		# A new game: the galaxy made behind the loading screen, a little a
		# frame (Galaxy.new_game_async), then the game.
		SaveGame.pending = {}
		SaveGame.travelling = false
		_on_space3d(false)


## The 3D game: the latest save continued (its galaxy loaded under the veil),
## or a new game (a new galaxy charted under the veil).
func _on_space3d(continue_save := false) -> void:
	Cosmos.arrive_from = ""
	if continue_save:
		LoadVeil.change_to(Cosmos.SCENE, "Continue", func(_progress): CosmosGame.begin(true), "Loading your save")
	else:
		LoadVeil.change_to(Cosmos.SCENE, "New game", func(progress):
			await Galaxy.new_game_async(progress, true)
			CosmosGame.begin(false)
			CosmosGame.start_on_foot(), "Charting the galaxy")   # (a new game: on foot on Amnissos, no ship yet)


func _on_save() -> void:
	var game := get_tree().current_scene
	if game.has_method("can_save") and not game.can_save():
		_flash_status("Can't save now")
		return
	_open_slots("save")


func _on_load() -> void:
	_open_slots("load")


## Saves the game into a slot (asked first when it would overwrite one).
func _save_to(slot: int) -> void:
	var game := get_tree().current_scene
	if not game.has_method("get_save_data"):
		return
	if SaveGame.has_save(slot) and _slot_confirm != slot:
		_slot_confirm = slot   # (a second click on it saves)
		_fill_slots()
		return
	_slot_confirm = 0
	if SaveGame.save_game(game.get_save_data(), slot):
		_flash_status("Game saved (slot %d)" % slot)
		GameLog.post("Game saved in slot %d" % slot, "info")
		_close_slots()
	else:
		_flash_status("Save failed!")
	_refresh_load_button()


func _load_from(slot: int) -> void:
	# (Re)loads the game scene, under a loading screen; it applies
	# SaveGame.pending in _ready() - a save made on a planet takes you back
	# down there.
	if not SaveGame.load_slot(slot):
		_flash_status("No valid save in slot %d" % slot)
		_refresh_load_button()


# --- The slot lists (Save / Load) -------------------------------------------------------------
# SaveGame.SLOTS slots, each a row: its number, when it was saved and where
# you were (the system, the planet if you were on one), your ship and
# credits; Save into it (an occupied one asks first: click again) or Load it,
# and a delete button. Esc or Back closes the list.

var _slots_panel: PanelContainer
var _slots_rows: VBoxContainer
var _slots_mode := "save"
var _slot_confirm := 0


func _open_slots(mode: String) -> void:
	_slots_mode = mode
	_slot_confirm = 0
	if _slots_panel == null:
		_slots_panel = PanelContainer.new()
		_slots_panel.name = "SlotsPanel"
		_slots_panel.custom_minimum_size = Vector2(900, 0)
		_slots_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 10)
		_slots_panel.add_child(v)
		_slots_rows = VBoxContainer.new()
		_slots_rows.add_theme_constant_override("separation", 6)
		v.add_child(_slots_rows)
		var back := UI.button("Back", _close_slots, 18)
		back.tooltip_text = "Back to the menu."
		back.custom_minimum_size = Vector2(0, 44)
		v.add_child(back)
		main_buttons.get_parent().add_child(_slots_panel)
		main_buttons.get_parent().move_child(_slots_panel, main_buttons.get_index() + 1)
	main_buttons.hide()
	_slots_panel.show()
	_fill_slots()


func _close_slots() -> void:
	if _slots_panel:
		_slots_panel.hide()
	main_buttons.show()
	if is_visible_in_tree():
		var cont: Button = main_buttons.get_node_or_null("ContinueButton")
		(cont if cont and cont.visible else %StartButton).grab_focus()


func _fill_slots() -> void:
	UI.clear(_slots_rows)
	_slots_rows.add_child(UI.section("SAVE GAME  ·  choose a slot" if _slots_mode == "save" else "LOAD GAME  ·  choose a save"))
	# (loading: the quicksave and the autosave first; saving: the numbered slots)
	var list: Array = SaveGame.all_slots() if _slots_mode == "load" else range(1, SaveGame.SLOTS + 1)
	for s_id in list:
		var slot: int = s_id
		var info := SaveGame.slot_info(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var num := UI.label({SaveGame.QUICK: "Q", SaveGame.AUTO: "A"}.get(slot, "%d" % slot), 22, NeonTheme.HEAD)
		num.tooltip_text = SaveGame.slot_name(slot)
		num.mouse_filter = Control.MOUSE_FILTER_PASS
		num.custom_minimum_size = Vector2(36, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(num)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		text.add_theme_constant_override("separation", 0)
		if info.is_empty():
			text.add_child(UI.label({SaveGame.QUICK: "No quicksave yet (F5)", SaveGame.AUTO: "No autosave yet"}.get(slot, "Empty slot"), 17, UI.TEXT_DIM))
		else:
			var sm: Dictionary = info.get("summary", {})
			var where := str(sm.get("system", "?"))
			if str(sm.get("planet", "")) != "":
				where = "on %s  ·  %s" % [sm["planet"], where]
			text.add_child(UI.label(("%s  ·  " % SaveGame.slot_name(slot) if slot > SaveGame.SLOTS else "") + where, 17))
			text.add_child(UI.label("%s  ·  %s  ·  %d drachmas" % [str(info.get("saved_at", "")).replace("T", "  "), sm.get("ship", "?"), int(sm.get("credits", 0))], 14, UI.TEXT_DIM))
		row.add_child(text)
		var b: Button
		if _slots_mode == "save":
			var confirming := _slot_confirm == slot
			b = UI.button("Overwrite?" if confirming else ("Save here" if info.is_empty() else "Save over"), _save_to.bind(slot), 16)
			if confirming:
				b.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4))
		else:
			b = UI.button("Load", _load_from.bind(slot), 16)
			b.disabled = info.is_empty()
			b.tooltip_text = ("Nothing saved here yet." if info.is_empty() else "Loads this save (%s); the game you're in, unsaved, is left." % SaveGame.slot_name(slot)) if overlay \
				else ("Nothing saved here yet." if info.is_empty() else "Loads this save (%s)." % SaveGame.slot_name(slot))
		if _slots_mode == "save":
			b.tooltip_text = "Saves your game here (%s)%s." % [SaveGame.slot_name(slot), "" if info.is_empty() else " - over the save in it: click again to confirm"]
		b.custom_minimum_size = Vector2(170, 44)
		row.add_child(b)
		var del := UI.button("", _delete_slot.bind(slot), 14)
		del.icon = EditorIcons.get_icon("delete")
		IconAnim.attach(del, "delete")
		del.tooltip_text = "Delete this save (click twice)."
		del.custom_minimum_size = Vector2(44, 44)
		del.disabled = info.is_empty()
		row.add_child(del)
		_slots_rows.add_child(row)
	if _slots_rows.get_child_count() > 1:
		var first: Control = _slots_rows.get_child(1)
		var btn := first.get_child(2) as Button
		if btn and not btn.disabled:
			btn.grab_focus.call_deferred()


var _delete_confirm := 0

func _delete_slot(slot: int) -> void:
	if _delete_confirm != slot:
		_delete_confirm = slot
		_flash_status("Click delete again to erase %s" % SaveGame.slot_name(slot).to_lower())
		return
	_delete_confirm = 0
	SaveGame.delete_slot(slot)
	_flash_status("%s deleted" % SaveGame.slot_name(slot))
	_fill_slots()
	_refresh_load_button()


func _on_quit_to_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(scene_file_path)


func _refresh_load_button() -> void:
	var stamp := SaveGame.saved_at()   # (the newest save)
	%LoadButton.disabled = stamp.is_empty()
	var cont: Button = main_buttons.get_node_or_null("ContinueButton")
	if cont:
		cont.visible = not stamp.is_empty()
		var latest := SaveGame.latest_slot()
		var sm: Dictionary = SaveGame.slot_info(latest).get("summary", {}) if latest > 0 else {}
		cont.tooltip_text = "Loads your latest save: %s%s%s." % [SaveGame.slot_name(latest),
			(" - " + str(sm.get("planet", "")) + ", " if str(sm.get("planet", "")) != "" else " - ") + str(sm.get("system", "")) if not sm.is_empty() else "",
			"  (" + stamp.replace("T", " ") + ")" if stamp != "" else ""]
	if overlay:
		return
	# On the title screen, show when the save was made.
	%StatusLabel.text = "Latest save: %s" % stamp.replace("T", "  ") if stamp else ""


func _flash_status(message: String) -> void:
	var label: Label = %StatusLabel
	label.text = message
	label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(1.2)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)


## Adds a "TEXT SIZE" section to the settings panel: one slider per kind of
## text (50%-300%). Changes apply immediately everywhere.
func _build_text_settings() -> void:
	var rows: VBoxContainer = %BackButton.get_parent()
	var at := %BackButton.get_index()
	var heading := Label.new()
	heading.text = "TEXT SIZE"
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", NeonTheme.HEAD)
	rows.add_child(heading)
	rows.move_child(heading, at)
	at += 1
	for category in Settings.TEXT_CATEGORIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var label := Label.new()
		label.text = Settings.TEXT_CATEGORIES[category]
		label.custom_minimum_size = Vector2(170, 0)
		label.add_theme_font_size_override("font_size", 20)
		row.add_child(label)
		var slider := HSlider.new()
		slider.min_value = Settings.TEXT_SCALE_MIN * 100.0
		slider.max_value = Settings.TEXT_SCALE_MAX * 100.0
		slider.step = Settings.TEXT_SCALE_STEP * 100.0
		slider.tick_count = 6        # 50, 100, 150, 200, 250, 300
		slider.tooltip_text = "The size of the %s text, %d%% to %d%% (100%% as made)." % [str(Settings.TEXT_CATEGORIES[category]).to_lower() if category != "hud" else "HUD's", roundi(Settings.TEXT_SCALE_MIN * 100.0), roundi(Settings.TEXT_SCALE_MAX * 100.0)]
		slider.ticks_on_borders = true
		slider.custom_minimum_size = Vector2(240, 32)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size = Vector2(70, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 20)
		row.add_child(value)
		# Icon-only button: put this slider back to its default (100%).
		var reset := Button.new()
		reset.icon = UI.reset_icon()
		reset.tooltip_text = "Reset to default (100%)"
		reset.custom_minimum_size = Vector2(40, 36)
		reset.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reset.focus_mode = Control.FOCUS_NONE
		reset.pressed.connect(func(): slider.value = 100.0)
		row.add_child(reset)
		slider.value_changed.connect(func(v):
			value.text = "%d%%" % roundi(v)
			reset.disabled = is_equal_approx(v, 100.0)
			Settings.set_text_scale(category, v / 100.0))
		rows.add_child(row)
		rows.move_child(row, at)
		at += 1
		_text_sliders[category] = [slider, value, reset]
	# Sound: master, music and effects volumes (effects play a sample as you move them).
	var sh := Label.new()
	sh.text = "SOUND"
	sh.add_theme_font_size_override("font_size", 18)
	sh.add_theme_color_override("font_color", NeonTheme.HEAD)
	rows.add_child(sh)
	rows.move_child(sh, at)
	at += 1
	for kind in Settings.VOLUMES:
		var srow := HBoxContainer.new()
		srow.add_theme_constant_override("separation", 12)
		var slabel := Label.new()
		slabel.text = Settings.VOLUMES[kind]
		slabel.custom_minimum_size = Vector2(170, 0)
		slabel.add_theme_font_size_override("font_size", 20)
		srow.add_child(slabel)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 5.0
		slider.custom_minimum_size = Vector2(240, 32)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.tooltip_text = {"master": "Everything's volume (0% = silent).", "music": "The music's volume (0% = off).",
			"sfx": "Sound effects volume (0% = off) - a sample plays as you move it.",
			"voice": "The characters' spoken dialogue (0% = off) - Kilon says a few words as you move it."}[kind]
		srow.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size = Vector2(70, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 20)
		srow.add_child(value)
		var reset := Button.new()
		reset.icon = UI.reset_icon()
		reset.tooltip_text = "Reset to default (%d%%)" % roundi(Settings.VOLUME_DEFAULTS[kind] * 100)
		reset.custom_minimum_size = Vector2(40, 36)
		reset.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reset.focus_mode = Control.FOCUS_NONE
		reset.pressed.connect(func(): slider.value = Settings.VOLUME_DEFAULTS[kind] * 100.0)
		srow.add_child(reset)
		slider.value = Settings.volume(kind) * 100.0
		value.text = "%d%%" % roundi(slider.value)
		reset.disabled = is_equal_approx(slider.value, Settings.VOLUME_DEFAULTS[kind] * 100.0)
		var sample_t := [0]
		slider.value_changed.connect(func(v):
			value.text = "%d%%" % roundi(v)
			reset.disabled = is_equal_approx(v, Settings.VOLUME_DEFAULTS[kind] * 100.0)
			Settings.set_volume(kind, v / 100.0)
			if kind != "music" and Time.get_ticks_msec() - sample_t[0] > 250:   # (a sample at the new volume)
				sample_t[0] = Time.get_ticks_msec()
				if kind == "voice":
					if not Voice._player.playing:
						Voice.speak("The thread is in your hands.", "Kilon Alios")
				else:
					Sfx.play("pirate/shot"))
		rows.add_child(srow)
		rows.move_child(srow, at)
		at += 1
		_volume_sliders[kind] = [slider, value, reset]
	var footer := HBoxContainer.new()
	var hint := Label.new()
	hint.text = "Changes apply immediately."
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", NeonTheme.TEXT)
	footer.add_child(hint)
	_settings_hint = hint
	# Resets every setting: resolution, fullscreen and all text sizes.
	var defaults := Button.new()
	defaults.text = "Restore Defaults"
	defaults.tooltip_text = "Resolution 1920 × 1080, windowed, all text at 100%, volumes: master 100%, music 70%, effects 100%, voices 80%; CRT filter off (on in attract mode), at its default look"
	defaults.add_theme_font_size_override("font_size", 16)
	defaults.pressed.connect(_restore_defaults)
	footer.add_child(defaults)
	rows.add_child(footer)
	rows.move_child(footer, at)


## The settings panel never grows past 150%, so it always fits on screen
## (you can't push the sliders out of reach); the rest of the menu goes to 200%.
## The Controls page's action names (their width follows the text size).
var _bind_names: Array[Label] = []


static func _bind_name_width() -> float:
	return 140.0 * clampf(Settings.font_scale("menu"), 1.0, 1.45)


func _apply_text_size() -> void:
	if _lazy:
		return   # (sized when it's built)
	UI.scale_fonts(self, "menu", 2.0)
	UI.scale_fonts(settings_panel, "menu", 1.5)
	if crt_panel:
		UI.scale_fonts(crt_panel, "menu", 1.5)
	_fit_controls()   # (the names and bindings fitted to the new text size)
	_fit.call_deferred()   # (bigger text: taller pages)


func _restore_defaults() -> void:
	Settings.reset_to_defaults()
	_sync_settings_ui()
	_sync_game_settings()
	_settings_hint.text = "All settings restored to default."
	var tween := create_tween()
	tween.tween_interval(2.0)
	tween.tween_callback(func(): _settings_hint.text = "Changes apply immediately.")


## Show the current settings in the controls (without triggering changes).
func _sync_settings_ui() -> void:
	for kind in _volume_sliders:
		var v := Settings.volume(kind) * 100.0
		_volume_sliders[kind][0].set_value_no_signal(v)
		_volume_sliders[kind][1].text = "%d%%" % roundi(v)
		_volume_sliders[kind][2].disabled = is_equal_approx(v, Settings.VOLUME_DEFAULTS[kind] * 100.0)
	for category in _text_sliders:
		var v := Settings.font_scale(category) * 100.0
		_text_sliders[category][0].set_value_no_signal(v)
		_text_sliders[category][1].text = "%d%%" % roundi(v)
		_text_sliders[category][2].disabled = is_equal_approx(v, 100.0)
	var index := _resolutions.find(Settings.resolution)
	resolution_option.select(index if index >= 0 else _resolutions.size() - 1)
	fullscreen_check.set_pressed_no_signal(Settings.fullscreen)
	resolution_option.disabled = false   # (fullscreen too: the world drawn at the resolution picked, scaled to the screen)
	_sync_crt_ui()


func _open_settings() -> void:
	if _lazy:
		_build_settings()   # (the Esc menu builds its settings when first wanted)
	_sync_settings_ui()
	_sync_game_settings()

	main_buttons.hide()
	settings_panel.show()
	_fit()
	if settings_tab == 0:
		resolution_option.grab_focus()


func _close_settings() -> void:
	settings_panel.hide()
	if crt_panel:
		crt_panel.hide()
	_listen_id = ""
	Settings.crt_preview = false
	main_buttons.show()
	_fit()
	if is_visible_in_tree():
		%StartButton.grab_focus()


func _on_resolution_selected(index: int) -> void:
	Settings.resolution = _resolutions[index]
	Settings.apply()
	Settings.save_settings()


func _on_fullscreen_toggled(on: bool) -> void:
	Settings.fullscreen = on
	Settings.apply()
	Settings.save_settings()



# --- The CRT filter page -------------------------------------------------------------------

## A "CRT filter" row on the settings page (the switch, and "Tune" for its own
## page), and that page: always on / in attract mode, and a slider for every
## parameter of the filter (Settings.CRT_PARAMS). While the page is open the
## filter shows, so you see what you tune.
func _build_crt_settings() -> void:
	var row := HBoxContainer.new()
	row.name = "CrtRow"
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = "CRT filter"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 20)
	row.add_child(label)
	_crt_check = CheckButton.new()
	_crt_check.tooltip_text = "An old CRT screen over the whole game: curved glass, scanlines, phosphor stripes."
	_crt_check.toggled.connect(func(on): Settings.set_crt_switch(false, on); _sync_crt_ui())
	row.add_child(_crt_check)
	var tune := Button.new()
	tune.name = "CrtTune"
	tune.text = "Tune..."
	tune.tooltip_text = "The CRT filter's own page: every parameter, with a live preview."
	tune.add_theme_font_size_override("font_size", 18)
	tune.pressed.connect(_open_crt)
	row.add_child(tune)
	var rows: VBoxContainer = %FullscreenCheck.get_parent().get_parent()
	rows.add_theme_constant_override("separation", 11)   # (room for this row)
	rows.add_child(row)
	# The FPS counter's switch, under it.
	var frow := HBoxContainer.new()
	frow.name = "FpsRow"
	frow.add_theme_constant_override("separation", 12)
	var flabel := Label.new()
	flabel.text = "FPS counter"
	flabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flabel.add_theme_font_size_override("font_size", 20)
	frow.add_child(flabel)
	_fps_check = CheckButton.new()
	_fps_check.tooltip_text = "A frame-rate readout in the bottom-right corner of the window: frames a second and the frame time."
	_fps_check.set_pressed_no_signal(Settings.fps_counter)
	_fps_check.toggled.connect(func(on): Settings.set_fps_counter(on))
	frow.add_child(_fps_check)
	rows.add_child(frow)
	rows.move_child(row, %FullscreenCheck.get_parent().get_index() + 1)
	rows.move_child(frow, row.get_index() + 1)
	# How the characters on foot are drawn: the 3D model, its rendered sprites, the classic sheets.
	var sprow := HBoxContainer.new()
	sprow.name = "CharacterGraphicsRow"
	sprow.add_theme_constant_override("separation", 12)
	var splabel := Label.new()
	splabel.text = "Characters drawn from"
	splabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	splabel.add_theme_font_size_override("font_size", 20)
	sprow.add_child(splabel)
	_graphics_pick = OptionButton.new()
	_graphics_pick.tooltip_text = "3D model: the automaton is its actual 3D model, drawn live - it turns smoothly and moves between the keyed frames.\nRendered sprites: pictures rendered from the models (30 frames a second, 8 views).\nClassic sprites: the original hand-drawn sheets (two poses) - skills still work, without their animations.\nTakes effect at the next landing."
	for m in Settings.CHARACTER_GRAPHICS:
		_graphics_pick.add_item(m[1])
	_graphics_pick.item_selected.connect(func(i): Settings.set_character_graphics(Settings.CHARACTER_GRAPHICS[i][0]))
	sprow.add_child(_graphics_pick)
	rows.add_child(sprow)
	rows.move_child(sprow, frow.get_index() + 1)
	_sync_graphics_pick()
	# The planets' ground as 3D geometry, or the 2D tiles.
	var trow := HBoxContainer.new()
	trow.name = "Terrain3DRow"
	trow.add_theme_constant_override("separation", 12)
	var tlabel := Label.new()
	tlabel.text = "3D terrain"
	tlabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tlabel.add_theme_font_size_override("font_size", 20)
	trow.add_child(tlabel)
	_terrain_check = CheckButton.new()
	_terrain_check.tooltip_text = "The planets' ground as real 3D geometry - every tile a square at its height, cliffs and ramps solid - seen by a 3D camera.\nOff: the 2D tiles, drawn as pictures (as before). Takes effect at the next landing."
	_terrain_check.set_pressed_no_signal(Settings.terrain_3d)
	_terrain_check.toggled.connect(func(on): Settings.set_terrain_3d(on))
	trow.add_child(_terrain_check)
	rows.add_child(trow)
	rows.move_child(trow, sprow.get_index() + 1)
	# Anti-aliasing (the 3D view).
	var arow := HBoxContainer.new()
	arow.name = "AntialiasRow"
	arow.add_theme_constant_override("separation", 12)
	var alabel := Label.new()
	alabel.text = "Anti-aliasing"
	alabel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	alabel.add_theme_font_size_override("font_size", 20)
	arow.add_child(alabel)
	_aa_pick = OptionButton.new()
	_aa_pick.tooltip_text = "Smooths the 3D view's jagged edges and shimmer.
FXAA: cheapest, a little soft. MSAA 2x / 4x / 8x: geometry's edges, sharper, costlier (with FXAA on top).
TAA: the steadiest stars and grass, with a touch of blur in motion. Applies at once."
	for m in Settings.ANTIALIAS:
		_aa_pick.add_item(m[1])
	_aa_pick.item_selected.connect(func(i): Settings.set_antialias(Settings.ANTIALIAS[i][0]))
	arow.add_child(_aa_pick)
	rows.add_child(arow)
	rows.move_child(arow, trow.get_index() + 1)

	crt_panel = PanelContainer.new()
	crt_panel.name = "CrtPanel"
	crt_panel.visible = false
	crt_panel.custom_minimum_size = Vector2(560, 0)
	crt_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	crt_panel.add_theme_stylebox_override("panel", settings_panel.get_theme_stylebox("panel"))
	settings_panel.get_parent().add_child(crt_panel)
	settings_panel.get_parent().move_child(crt_panel, settings_panel.get_index() + 1)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	crt_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "CRT FILTER"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_font_override("font", NeonTheme.heavy_font())
	heading.add_theme_color_override("font_color", NeonTheme.HEAD)
	box.add_child(heading)
	for sw in [[false, "Always on", "The filter over the whole game, all the time."],
			[true, "In attract mode", "The filter while the game plays itself on the title screen."]]:
		var srow := HBoxContainer.new()
		var sl := Label.new()
		sl.text = sw[1]
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.add_theme_font_size_override("font_size", 20)
		srow.add_child(sl)
		var check := CheckButton.new()
		check.tooltip_text = sw[2]
		var attract: bool = sw[0]
		check.toggled.connect(func(on): Settings.set_crt_switch(attract, on); _sync_crt_ui())
		srow.add_child(check)
		box.add_child(srow)
		_crt_switches[attract] = check
	var sub := Label.new()
	sub.text = "LOOK"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", NeonTheme.HEAD)
	box.add_child(sub)
	for p in Settings.CRT_PARAMS:
		var id: String = p[0]
		var prow := HBoxContainer.new()
		prow.add_theme_constant_override("separation", 12)
		var pl := Label.new()
		pl.text = p[1]
		pl.custom_minimum_size = Vector2(170, 0)
		pl.add_theme_font_size_override("font_size", 20)
		pl.tooltip_text = p[8]
		pl.mouse_filter = Control.MOUSE_FILTER_PASS
		prow.add_child(pl)
		var slider := HSlider.new()
		slider.min_value = p[2]
		slider.max_value = p[3]
		slider.step = p[4]
		slider.custom_minimum_size = Vector2(240, 30)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.tooltip_text = p[8]
		prow.add_child(slider)
		var value := Label.new()
		value.custom_minimum_size = Vector2(80, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 20)
		prow.add_child(value)
		var reset := Button.new()
		reset.icon = UI.reset_icon()
		reset.tooltip_text = "Reset to default (%s)" % _crt_text(p, p[5])
		reset.custom_minimum_size = Vector2(40, 34)
		reset.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		reset.focus_mode = Control.FOCUS_NONE
		reset.pressed.connect(func(): slider.value = p[5])
		prow.add_child(reset)
		slider.value_changed.connect(func(v):
			value.text = _crt_text(p, v)
			reset.disabled = is_equal_approx(v, p[5])
			Settings.set_crt(id, v))
		box.add_child(prow)
		_crt_sliders[id] = [slider, value, reset, p]
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	var hint := Label.new()
	hint.text = "Preview: the filter shows while this page is open."
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", NeonTheme.TEXT)
	footer.add_child(hint)
	var defaults := Button.new()
	defaults.name = "CrtDefaults"
	defaults.text = "Default Look"
	defaults.tooltip_text = "Every slider on this page back to its default (the switches stay)."
	defaults.add_theme_font_size_override("font_size", 16)
	defaults.pressed.connect(func(): Settings.reset_crt(); _sync_crt_ui())
	footer.add_child(defaults)
	box.add_child(footer)
	var back := Button.new()
	back.name = "CrtBack"
	back.text = "Back"
	back.tooltip_text = "Back to the settings (the CRT filter's values are already kept)."
	back.custom_minimum_size = Vector2(0, 44)
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(_close_crt)
	box.add_child(back)


## A CRT parameter's value as shown: 0.38 -> "38%", 3.0 -> "3.0 px".
func _crt_text(p: Array, v: float) -> String:
	var shown: float = v * float(p[6])
	if p[7] == "%":
		return "%d%%" % roundi(shown)
	if p[7] == "":
		return "%.1f" % shown
	return "%.1f%s" % [shown, p[7]]


func _sync_graphics_pick() -> void:
	if _terrain_check:
		_terrain_check.set_pressed_no_signal(Settings.terrain_3d)
	if _aa_pick:
		for i in Settings.ANTIALIAS.size():
			if Settings.ANTIALIAS[i][0] == Settings.antialias:
				_aa_pick.select(i)
	if _graphics_pick == null:
		return
	for i in Settings.CHARACTER_GRAPHICS.size():
		if Settings.CHARACTER_GRAPHICS[i][0] == Settings.character_graphics:
			_graphics_pick.select(i)


func _sync_crt_ui() -> void:
	if _crt_check == null:
		return
	_crt_check.set_pressed_no_signal(Settings.crt_on)
	if _fps_check:
		_fps_check.set_pressed_no_signal(Settings.fps_counter)
	_sync_graphics_pick()
	for attract in _crt_switches:
		_crt_switches[attract].set_pressed_no_signal(Settings.crt_attract if attract else Settings.crt_on)
	for id in _crt_sliders:
		var e: Array = _crt_sliders[id]
		var v: float = Settings.crt.get(id, e[3][5])
		e[0].set_value_no_signal(v)
		e[1].text = _crt_text(e[3], v)
		e[2].disabled = is_equal_approx(v, e[3][5])


func _open_crt() -> void:
	if _lazy:
		_build_settings()   # (the Esc menu builds its settings when first wanted)
	_sync_crt_ui()
	settings_panel.hide()
	crt_panel.show()
	_fit()
	Settings.crt_preview = true
	_crt_switches[false].grab_focus()


func _close_crt() -> void:
	crt_panel.hide()
	Settings.crt_preview = false
	_sync_settings_ui()
	settings_panel.show()
	_fit()
	%BackButton.grab_focus()



# --- The Controls tab ---------------------------------------------------------------------

## The settings' CONTROLS tab: every action (Keybinds.ACTIONS) by group, with
## its two keys and its gamepad input. Click a binding, then press the key /
## button to put there (Esc cancels; right-click clears it). Clashes within a
## group show in red.
var _bind_buttons := {}       # "<id>|<slot>" -> Button
var _controls_hint: Label
var _pad_label: Label
var _listen_id := ""
var _listen_slot := 0


## Key groups shown under the group before them (Game under Toolbar).
const SHARED_COLUMN := ["Game"]

func _build_controls() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "ControlsPage"
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	_controls_hint = Label.new()
	_controls_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_hint.custom_minimum_size.x = 300
	_controls_hint.add_theme_font_size_override("font_size", 15)
	_controls_hint.add_theme_color_override("font_color", UI.TEXT_DIM)
	top.add_child(_controls_hint)
	_pad_label = Label.new()
	_pad_label.add_theme_font_size_override("font_size", 15)
	_pad_label.add_theme_color_override("font_color", NeonTheme.HEAD)
	top.add_child(_pad_label)
	var all := Button.new()
	all.text = "Reset all keys"
	all.tooltip_text = "Every key and gamepad binding back to the defaults."
	all.add_theme_font_size_override("font_size", 16)
	all.pressed.connect(func(): Keybinds.reset(); _sync_controls())
	top.add_child(all)
	box.add_child(top)
	# The groups side by side (Menus | Flight | Toolbar) - as many as the window's width fits, the rest on
	# the next line (wider than the window, the panel ran off its edges).
	var cols := HFlowContainer.new()
	cols.name = "ControlsCols"
	cols.add_theme_constant_override("h_separation", 28)
	cols.add_theme_constant_override("v_separation", 12)
	box.add_child(cols)
	var col: VBoxContainer = null
	var group := ""
	for a in Keybinds.ACTIONS:
		if a[1] != group:
			group = a[1]
			if group in SHARED_COLUMN and col:
				# (a short group under the one before it, not a column of its own:
				# three columns fit the window at any text size)
				var gap := Control.new()
				gap.custom_minimum_size.y = 8
				col.add_child(gap)
			else:
				col = VBoxContainer.new()
				col.add_theme_constant_override("separation", 1)   # (rows close together: every action on the page at any text size)
				cols.add_child(col)
			var gh := HBoxContainer.new()
			var gl := Label.new()
			gl.text = group.to_upper()
			gl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			gl.add_theme_font_size_override("font_size", 16)
			gl.add_theme_font_override("font", NeonTheme.heavy_font())
			gl.add_theme_color_override("font_color", NeonTheme.HEAD)
			gh.add_child(gl)
			for t in ["KEY", "ALT KEY", "GAMEPAD", ""]:
				var tl := Label.new()
				tl.text = t
				tl.custom_minimum_size = Vector2(104 if t != "" else 32, 0)
				tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				tl.add_theme_font_size_override("font_size", 14)
				tl.add_theme_color_override("font_color", UI.TEXT_DIM)
				gh.add_child(tl)
			col.add_child(gh)
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 4)
		var l := Label.new()
		l.text = a[2]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# (as wide as its column's longest name, whole - _fit_controls; the groups wrap when they don't fit)
		l.custom_minimum_size.x = _bind_name_width()
		_bind_names.append(l)
		l.add_theme_font_size_override("font_size", 14)
		l.tooltip_text = a[2]   # (the name in full, when it's clipped)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		r.add_child(l)
		for slot in 3:
			var b := Button.new()
			b.custom_minimum_size = Vector2(104, 26)
			b.add_theme_font_size_override("font_size", 14)
			b.clip_text = true
			b.pressed.connect(_start_listen.bind(a[0], slot))
			b.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					Keybinds.set_bind(a[0], slot, "")
					_sync_controls())
			b.tooltip_text = "Click, then press the %s for \"%s\" (Esc cancels). Right-click clears it." % ["gamepad button / stick / trigger" if slot == 2 else "key", a[2]]
			_bind_buttons["%s|%d" % [a[0], slot]] = b
			r.add_child(b)
		var reset := Button.new()
		reset.icon = UI.reset_icon()
		reset.custom_minimum_size = Vector2(32, 26)
		reset.focus_mode = Control.FOCUS_NONE
		reset.tooltip_text = "Back to the defaults: " + " / ".join(Keybinds.defaults(a[0]).filter(func(x): return x != "").map(func(x): return Keybinds.spec_text(x)))
		reset.pressed.connect(func(): Keybinds.reset(a[0]); _sync_controls())
		r.add_child(reset)
		col.add_child(r)
	_sync_controls()
	return box


func _sync_controls() -> void:
	if _lazy:
		_build_settings()   # (the Esc menu builds its settings when first wanted)
	_pad_label.text = ("Gamepad: " + Input.get_joy_name(Input.get_connected_joypads()[0]) + "  ") if Keybinds.pad_connected() else "No gamepad  "
	for a in Keybinds.ACTIONS:
		for slot in 3:
			var b: Button = _bind_buttons["%s|%d" % [a[0], slot]]
			var spec: String = Keybinds.binds[a[0]][slot]
			var listening: bool = _listen_id == a[0] and _listen_slot == slot
			b.text = "press..." if listening else (Keybinds.spec_text(spec) if spec != "" else "-")
			var clash := not listening and not Keybinds.clashes(a[0], spec).is_empty()
			if clash:
				b.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
			else:
				b.remove_theme_color_override("font_color")
	if _listen_id == "":
		_controls_hint.text = "Click a binding, then press the key, mouse button or gamepad input. Right-click clears one; red: used twice."
	_fit_controls()


## The Controls page's columns fitted to their text: each column's action names as wide as its longest (a
## gap after them - never cut off), every binding button and its heading as wide as the longest binding
## shown. Done again when the bindings or the text size change.
func _fit_controls() -> void:
	var flow := settings_panel.find_child("ControlsCols", true, false) if settings_panel else null
	if flow == null:
		return
	var bw := 0.0
	var buttons := []
	for b in _bind_buttons.values():
		if not is_instance_valid(b):
			continue
		var bt := b as Button
		buttons.append(bt)
		var f: Font = bt.get_theme_font("font")
		var fs: int = bt.get_theme_font_size("font_size")
		for txt in [bt.text, "press..."]:
			bw = maxf(bw, f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var pad := 24.0
	if not buttons.is_empty():
		var sb: StyleBox = (buttons[0] as Button).get_theme_stylebox("normal")
		if sb:
			pad = sb.get_minimum_size().x + 14.0   # (its style's own margins - the accent bar - and room either side)
	bw = maxf(90.0, ceilf(bw + pad))
	for bt in buttons:
		bt.custom_minimum_size.x = bw
	# (a group split over two columns - a menu built before its actions were in order: its rows put back
	# with the rest of it, the empty column gone)
	var seen := {}   # group -> [column, the index after its last row]
	for col in flow.get_children():
		var cur := ""
		var k := 0
		while k < col.get_child_count():
			var row = col.get_child(k)
			if row is HBoxContainer and row.get_child_count() > 1 and not (row.get_child(1) is Button):
				cur = str((row.get_child(0) as Label).text)
				if seen.has(cur) and seen[cur][0] != col:
					# (moved: this header's rows into the earlier column)
					var dest: Node = seen[cur][0]
					var at: int = seen[cur][1]
					col.remove_child(row)
					row.queue_free()
					while k < col.get_child_count() and col.get_child(k) is HBoxContainer and col.get_child(k).get_child(1) is Button:
						var mv = col.get_child(k)
						col.remove_child(mv)
						dest.add_child(mv)
						dest.move_child(mv, at)
						at += 1
					seen[cur][1] = at
					continue
				seen[cur] = [col, k + 1]
			elif row is HBoxContainer and row.get_child_count() > 1 and seen.has(cur) and seen[cur][0] == col:
				seen[cur][1] = k + 1
			k += 1
	for col in flow.get_children():
		if col.get_child_count() == 0:
			col.queue_free()
	# (one name width for every column - the buttons line up down the page; a longer name wraps onto two
	# lines or more instead of pushing its buttons along)
	var names := []
	var nw := 0.0
	for col in flow.get_children():
		if col.is_queued_for_deletion():
			continue
		for row in col.get_children():
			if not (row is HBoxContainer) or row.get_child_count() < 2:
				continue
			(row as HBoxContainer).add_theme_constant_override("separation", 4)
			if row.get_child(1) is Button:
				# (an action's row: its name, its three bindings, its reset)
				var l := row.get_child(0) as Label
				for k in range(1, row.get_child_count()):
					(row.get_child(k) as Control).size_flags_vertical = Control.SIZE_SHRINK_CENTER   # (its own height, beside a name on two lines)
				l.clip_text = false
				l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				l.size_flags_horizontal = Control.SIZE_FILL
				l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				nw = maxf(nw, l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
				names.append(l)
			else:
				# (the group's heading row: KEY / ALT KEY / GAMEPAD over the buttons)
				var gl := row.get_child(0) as Label
				for k in range(1, row.get_child_count()):
					var hl := row.get_child(k) as Label
					if hl and hl.text != "":
						hl.custom_minimum_size.x = bw
				names.append(gl)
	var fs0 := 15.0
	if not names.is_empty():
		fs0 = float((names[0] as Label).get_theme_font_size("font_size"))
	nw = minf(nw, fs0 * 15.0)   # (about fifteen letters' width at most: longer names take two lines)
	for l in names:
		(l as Label).custom_minimum_size.x = ceilf(nw + 16.0)   # (a gap before the buttons)
		(l as Label).size_flags_horizontal = Control.SIZE_FILL


func _start_listen(id: String, slot: int) -> void:
	_listen_id = id
	_listen_slot = slot
	_controls_hint.text = "Press the %s for \"%s\" - Esc cancels." % ["gamepad button, stick or trigger" if slot == 2 else "key or mouse button", Keybinds.label(id)]
	_sync_controls()


## While listening: the input pressed becomes the binding. True if it used the event.
func _listen(ev: InputEvent) -> bool:
	if ev is InputEventMouseButton and _listen_slot != 2 and ev.pressed and Keybinds.MOUSE_BUTTONS.has(ev.button_index):
		pass   # (a mouse button, in a key slot: bound like a key - with its modifiers)
	elif ev is InputEventMouse:
		return false
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		_listen_id = ""
		_sync_controls()
		return true
	var pad := _listen_slot == 2
	if pad != (ev is InputEventJoypadButton or ev is InputEventJoypadMotion) and not ev is InputEventMouseButton:
		return ev is InputEventKey or ev is InputEventJoypadButton   # (the wrong kind: swallowed, still listening)
	var spec := Keybinds.spec_of(ev)
	if spec == "":
		return true
	var id := _listen_id
	var b: Button = _bind_buttons["%s|%d" % [id, _listen_slot]]
	var others := Keybinds.clashes(id, spec)
	_listen_id = ""
	if others.is_empty():
		Keybinds.set_bind(id, _listen_slot, spec)
	else:   # (no two actions on one key: refused - the binding kept as it was)
		_controls_hint.text = "%s is already used for: %s - not changed. Pick another, or rebind that first." % [Keybinds.spec_text(spec), ", ".join(others.map(func(o): return Keybinds.label(o)))]
	_sync_controls()
	b.grab_focus.call_deferred()
	return true


# --- Tabs, and fitting the window --------------------------------------------------------

## The settings in tabs - DISPLAY (resolution, fullscreen, CRT filter, FPS
## counter), TEXT (sizes), SOUND (volumes), CONTROLS (keys and gamepad) - in
## a scroll area as tall as the window allows (see _fit): the panel never
## leaves the window, whatever its size or the text size.
const SETTINGS_TABS := ["DISPLAY", "TEXT", "SOUND", "CONTROLS", "GAME"]
var settings_tab := 0
var _settings_bar: HBoxContainer
var _settings_pages: Array[Control] = []
var _settings_scroll: ScrollContainer
var _crt_scroll: ScrollContainer


# --- The GAME tab: autosaves ---------------------------------------------------------------------

var _autosave_option: OptionButton
var _autosave_events: CheckButton
var _day_option: OptionButton


func _build_game_settings() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.name = "GamePage"
	box.add_theme_constant_override("separation", 12)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var l := UI.label("Autosave", 20)
	l.custom_minimum_size.x = 260
	row.add_child(l)
	_autosave_option = OptionButton.new()
	for m in Settings.AUTOSAVE_CHOICES:
		_autosave_option.add_item("Off" if m == 0 else "Every %d minutes" % m)
	_autosave_option.add_theme_font_size_override("font_size", 18)
	_autosave_option.custom_minimum_size = Vector2(260, 40)
	_autosave_option.tooltip_text = "How often the game saves itself into the Autosave slot (not while you're under attack)."
	_autosave_option.item_selected.connect(func(i: int):
		Settings.autosave_minutes = Settings.AUTOSAVE_CHOICES[i]
		Settings.save_settings())
	row.add_child(_autosave_option)
	box.add_child(row)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 16)
	var l2 := UI.label("Autosave on docking, arriving\nin a system and landing", 20)
	l2.custom_minimum_size.x = 260
	row2.add_child(l2)
	_autosave_events = CheckButton.new()
	_autosave_events.tooltip_text = "Also autosave whenever you dock at a station, come through a gate into a new system, or land on a planet."
	_autosave_events.toggled.connect(func(on: bool):
		Settings.autosave_events = on
		Settings.save_settings())
	row2.add_child(_autosave_events)
	box.add_child(row2)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 16)
	var l3 := UI.label("Day length", 20)
	l3.custom_minimum_size.x = 260
	row3.add_child(l3)
	_day_option = OptionButton.new()
	for d in Settings.DAY_LENGTHS:
		_day_option.add_item(str(d[1]))
	_day_option.add_theme_font_size_override("font_size", 18)
	_day_option.custom_minimum_size = Vector2(260, 40)
	_day_option.tooltip_text = "How long a day and a night last on the worlds (each world turns on its own axis). Changed in play, the worlds go on from where they are."
	_day_option.item_selected.connect(func(i: int):
		Settings.set_day_length(float(Settings.DAY_LENGTHS[i][0])))
	row3.add_child(_day_option)
	box.add_child(row3)
	var hint := UI.label("Autosaves go into their own slot (Autosave, at the top of the Load list), never into your six.\nF5 quicksaves and F9 quickloads at any time (Settings > Controls to rebind).", 15, UI.TEXT_DIM)
	box.add_child(hint)
	_sync_game_settings()
	return box


func _sync_game_settings() -> void:
	if _autosave_option == null:
		return
	_autosave_option.select(maxi(0, Settings.AUTOSAVE_CHOICES.find(Settings.autosave_minutes)))
	_autosave_events.set_pressed_no_signal(Settings.autosave_events)
	var di := 0
	for i in Settings.DAY_LENGTHS.size():
		if is_equal_approx(float(Settings.DAY_LENGTHS[i][0]), Settings.day_length):
			di = i
	_day_option.select(di)


func _tabify_settings() -> void:
	var rows: VBoxContainer = %BackButton.get_parent()
	var pages: Array[VBoxContainer] = []
	for i in SETTINGS_TABS.size():
		var pg := VBoxContainer.new()
		pg.name = SETTINGS_TABS[i].capitalize() + "Page"
		pg.add_theme_constant_override("separation", 11)
		pages.append(pg)
	# The rows as built, in order: heading, display rows, TEXT SIZE + its
	# sliders, SOUND + its sliders, the footer, Back.
	var page := 0
	for c in rows.get_children():
		if c.name == "Heading" or c == %BackButton or (c is HBoxContainer and c.get_child_count() > 0 and c.get_child(0) == _settings_hint):
			continue
		if c is Label and c.text == "TEXT SIZE":
			page = 1
		elif c is Label and c.text == "SOUND":
			page = 2
		if c is Label and c.text in ["TEXT SIZE", "SOUND"]:
			c.queue_free()   # (the tab says it)
			continue
		rows.remove_child(c)
		pages[page].add_child(c)
	pages[3].add_child(_build_controls())
	pages[4].add_child(_build_game_settings())
	_settings_bar = UI.tab_bar(SETTINGS_TABS, show_settings_tab, Color(), true, [
		"Display      [Q / E]\nThe window's size, fullscreen, the CRT filter, the frame-rate readout, anti-aliasing.",
		"Text      [Q / E]\nThe size of each kind of text: the HUD, story dialogue, menus, labels in space.",
		"Sound      [Q / E]\nThe volumes: everything, music, sound effects, voices.",
		"Controls      [Q / E]\nEvery action's key and gamepad button: click one, then press the new key.",
		"Game      [Q / E]\nAutosave: how often, and on docking, jumping and landing."])
	rows.add_child(_settings_bar)
	rows.move_child(_settings_bar, rows.get_node("Heading").get_index() + 1)
	_settings_scroll = ScrollContainer.new()
	_settings_scroll.name = "SettingsScroll"
	_settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_settings_scroll.follow_focus = true
	rows.add_child(_settings_scroll)
	rows.move_child(_settings_scroll, _settings_bar.get_index() + 1)
	var holder := MarginContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_theme_constant_override("margin_right", 14)   # (clear of the scroll bar)
	_settings_scroll.add_child(holder)
	for pg in pages:
		holder.add_child(pg)
		_settings_pages.append(pg)
	settings_panel.custom_minimum_size.x = 860
	# The CRT page: its rows scroll too.
	var box: VBoxContainer = crt_panel.get_child(0).get_child(0)
	var margin: MarginContainer = crt_panel.get_child(0)
	margin.remove_child(box)
	_crt_scroll = ScrollContainer.new()
	_crt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_crt_scroll.follow_focus = true
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crt_scroll.add_child(box)
	margin.add_child(_crt_scroll)
	get_viewport().size_changed.connect(_fit)
	show_settings_tab(0)


func show_settings_tab(i: int) -> void:
	if _lazy:
		_build_settings()   # (the Esc menu builds its settings when first wanted)
	settings_tab = i
	UI.select_tab(_settings_bar, i)
	for k in _settings_pages.size():
		_settings_pages[k].visible = k == i
	_listen_id = ""
	if i == 3:
		_sync_controls()
	_fit.call_deferred()


## Gamepad LB / RB, Q / E (Keybinds): the settings' tabs while they show.
func cycle_tab(d: int) -> void:
	if _lazy:
		_build_settings()   # (the Esc menu builds its settings when first wanted)
	if settings_panel.visible:
		show_settings_tab(wrapi(settings_tab + d, 0, SETTINGS_TABS.size()))


## Sizes the settings' and the CRT page's scroll areas so their panels fit
## the window (with a margin): as tall as the tab showing when there's room,
## else the window's height less the panel's own chrome. The title hides
## while either shows (it alone is a quarter of the window).
func _fit() -> void:
	if fullscreen_check and fullscreen_check.button_pressed != Settings.fullscreen:
		fullscreen_check.set_pressed_no_signal(Settings.fullscreen)   # (left fullscreen some other way: shown)
	if not Settings.display_changed.is_connected(_fit):
		Settings.display_changed.connect(_fit)   # (the window changed some other way: the switch shows it)
	if _settings_scroll == null or not is_inside_tree():
		return
	if not has_meta("controls_fitted"):
		set_meta("controls_fitted", true)
		_fit_controls()   # (a menu built before the columns fitted their text: fitted once - self-healing)
	var avail := get_viewport().get_visible_rect().size.y - 48.0
	$Center/Layout.get_child(0).visible = not (settings_panel.visible or crt_panel.visible)
	var tallest := 0.0
	var widest := 0.0
	for pg in _settings_pages:
		var cpg: Node = pg.find_child("ControlsPage", true, false)   # (the page built inside the tab's own page)
		if cpg == null and pg.name == "ControlsPage":
			cpg = pg
		if cpg and cpg.get_child_count() > 1 and cpg.get_child(1) is HBoxContainer:
			# (a Controls page built before its columns wrapped: its row of columns made a flow - self-healing)
			var old_row: HBoxContainer = cpg.get_child(1)
			var flow2 := HFlowContainer.new()
			flow2.name = "ControlsCols"
			flow2.add_theme_constant_override("h_separation", 28)
			flow2.add_theme_constant_override("v_separation", 12)
			for c in old_row.get_children():
				old_row.remove_child(c)
				flow2.add_child(c)
			cpg.add_child(flow2)
			cpg.move_child(flow2, 1)
			old_row.queue_free()
		var m := pg.get_combined_minimum_size()
		widest = maxf(widest, m.x)   # (one width for every tab: the panel doesn't jump sideways)
		var flow := pg.find_child("ControlsCols", true, false) as HFlowContainer
		if flow:
			# (as wide as its widest key group - the groups one under another: the panel no wider than the
			# settings need, its other tabs not stretched across the screen)
			var ws := []
			for c in flow.get_children():
				if not (c as Node).is_queued_for_deletion():
					ws.append((c as Control).get_combined_minimum_size().x)
			ws.sort()
			ws.reverse()
			var row := float(ws[0]) if not ws.is_empty() else 0.0   # (its widest group: the others under it)
			widest = maxf(widest, row)
	# (never wider than the window: the panel's margins, the scroll bar's room and a gap each side kept)
	widest = minf(widest, get_viewport().get_visible_rect().size.x - 48.0 - 14.0 - 80.0)
	# (one height for every tab - the tallest's, within the window: the panel doesn't jump as tabs change)
	for pg in _settings_pages:
		tallest = maxf(tallest, pg.get_combined_minimum_size().y)
		var flow_now := pg.find_child("ControlsCols", true, false) as HFlowContainer
		if flow_now:
			# (wrapped key groups: their height comes with the width they're laid out at - fitted again once they are)
			tallest = maxf(tallest, flow_now.size.y + 60.0)
			# (laid out or not yet: its groups one under another at this width - their heights added up)
			var stack := 60.0
			for c in flow_now.get_children():
				if not (c as Node).is_queued_for_deletion():
					stack += (c as Control).get_combined_minimum_size().y + 12.0
			tallest = maxf(tallest, stack)
			if not flow_now.resized.is_connected(_fit):
				flow_now.resized.connect(_fit, CONNECT_DEFERRED)
	_settings_scroll.custom_minimum_size.x = widest + 14.0
	var box: Control = _crt_scroll.get_child(0)
	_crt_scroll.custom_minimum_size.x = box.get_combined_minimum_size().x
	# Everything else in the layout (the status line, the spacing) counts too.
	var layout: Control = $Center/Layout
	_settings_scroll.custom_minimum_size.y = 0.0
	_crt_scroll.custom_minimum_size.y = 0.0
	var chrome := layout.get_combined_minimum_size().y
	if settings_panel.visible:
		_settings_scroll.custom_minimum_size.y = maxf(120.0, minf(tallest, avail - chrome))
	if crt_panel.visible:
		_crt_scroll.custom_minimum_size.y = maxf(120.0, minf(box.get_combined_minimum_size().y, avail - chrome))
	layout.reset_size()
