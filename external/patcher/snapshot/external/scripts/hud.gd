extends CanvasLayer
## In-game HUD: shield/hull bars, minimap, kill counter, hint, game-over panel.

const GAME_SCENE := "res://main.tscn"
const MENU_SCENE := "res://main_menu.tscn"

@onready var shield_bar: ProgressBar = %ShieldBar
@onready var hull_bar: ProgressBar = %HullBar
@onready var shield_value: Label = %ShieldValue
@onready var hull_value: Label = %HullValue
@onready var minimap: Control = %Minimap
@onready var hint: Label = %Hint
@onready var game_over: Control = %GameOver
@onready var toolbar: Control = %Toolbar
@onready var dock_prompt: Label = %DockPrompt
@onready var message: Label = %Message
@onready var credits_value: Label = %CreditsValue
@onready var mission_tracker: Label = %MissionTracker

var _message_tween: Tween
var event_log: GameLog
var _quest: Node
var _quest_title: Label
var _quest_objective: Label
var _quest_gap: Control
var _boss_bar: BossBar
var gauge: HealthGauge
var mining_panel: MiningPanel


## Re-styles for the GUI palette (NeonTheme).
func restyle() -> void:
	_neon_styles()


## Neon look for the status panel, bars and game-over box (scene styles).
func _neon_styles() -> void:
	add_to_group("neon_restyle")
	$Status.add_theme_stylebox_override("panel", StyleBoxEmpty.new())   # (the gauge stands on its own: no panel)
	var over := NeonTheme.box(NeonTheme.PINK, NeonTheme.hi_bg(0.94, 0.08), 2, 16, 16)
	$GameOver/Panel.add_theme_stylebox_override("panel", over)
	for bar_path in ["Status/Margin/Rows/ShieldRow/ShieldBar", "Status/Margin/Rows/HullRow/HullBar", "Status/Margin/Rows/FuelRow/FuelBar"]:
		var bar := get_node_or_null(bar_path) as ProgressBar
		if bar == null:
			continue
		var old_fill := bar.get_theme_stylebox("fill") as StyleBoxFlat
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(NeonTheme.BG, 0.9)
		bg.border_color = Color(NeonTheme.CYAN, 0.3)
		bg.set_border_width_all(1)
		bg.corner_radius_top_left = 5
		bg.corner_radius_bottom_right = 5
		bg.corner_detail = 1
		bg.skew = Vector2(0.3, 0)
		var fill := bg.duplicate()
		# Shields in the second colour (steel blue); the hull keeps its health colour.
		var col: Color = NeonTheme.INFO if bar_path.ends_with("ShieldBar") else (NeonTheme.CYAN if bar_path.ends_with("FuelBar") else (old_fill.bg_color if old_fill else NeonTheme.CYAN))
		fill.bg_color = col
		fill.border_color = col.lightened(0.5)
		fill.shadow_color = Color(col, 0.45)
		fill.shadow_size = 5
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fill)


func _ready() -> void:
	_neon_styles()
	_build_left_column()
	Settings.text_scale_changed.connect(_apply_text_size)
	_apply_text_size()
	game_over.hide()
	%RestartButton.pressed.connect(_on_restart)
	%LoadButton.pressed.connect(_on_load)
	%MenuButton.pressed.connect(_on_menu)
	EditorIcons.dress(%RestartButton, "restart", EditorIcons.tip("Respawn", "", "A new ship at the nearest station. Your main quest, missions, reputation and everything else\nare kept; you lose your cargo and pay 10% of your drachmas in insurance.\n(A new game: Main Menu > New Game.)"))
	EditorIcons.dress(%LoadButton, "reload", EditorIcons.tip("Load saved game", "", "Continues from your last save (made from the Esc menu).\nDisabled when there is no saved game."))
	EditorIcons.dress(%MenuButton, "menu", EditorIcons.tip("Main menu", "", "Returns to the title screen. Unsaved progress is lost."))


func bind(ship: Node2D, data: Node) -> void:
	minimap.ship = ship
	toolbar.ship = ship
	toolbar.data = data
	ship.health_changed.connect(_on_health_changed)
	ship.message.connect(flash_message)
	_on_health_changed(ship.hull, ship.max_hull, ship.shields, ship.max_shields)
	data.changed.connect(func(): credits_value.text = UI.money(data.credits))
	credits_value.text = UI.money(data.credits)
	# The health gauge in place of the shield and hull bars: the ship's outline
	# filled red as high as its hull, in a blue ring filled as high as its
	# shields, the afflictions round it (HealthGauge).
	gauge = HealthGauge.new()
	gauge.which = "ship"
	gauge.fuel = func(): return [data.fuel_level(), data.fuel_max(), Shipyard.FUEL_JUMP]   # (the amber ring outside the shield's)
	gauge.read = func(): return [ship.hull, ship.max_hull, ship.shields, ship.max_shields]
	gauge.condition = func(): return data.condition
	gauge.shape_source = func(): return ship.sprite.texture if is_instance_valid(ship) and ship.sprite else null
	gauge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	$Status/Margin/Rows.add_child(gauge)
	$Status/Margin/Rows.move_child(gauge, 0)
	$Status/Margin/Rows/ShieldRow.visible = false
	$Status/Margin/Rows/HullRow.visible = false
	$Status/Margin/Rows/CreditsRow.visible = false   # (your drachmas: at stations and in the inventory)
	$Status/Margin/Rows/FuelRow.visible = false      # (fuel: the gauge's outer ring)
	# The mining readout above the toolbar while you mine a rock (MiningPanel).
	mining_panel = MiningPanel.new()
	mining_panel.ship = ship
	mining_panel.anchor_left = 0.5
	mining_panel.anchor_right = 0.5
	mining_panel.anchor_top = 1.0
	mining_panel.anchor_bottom = 1.0
	mining_panel.offset_left = -280
	mining_panel.offset_right = 280
	mining_panel.offset_top = -330
	mining_panel.offset_bottom = -198
	add_child(mining_panel)


func bind_missions(missions: Node) -> void:
	var update := func():
		var lines := []
		if not missions.active.is_empty():
			lines.append("MISSIONS")
		for m in missions.active:
			lines.append("%s  -  %s" % [m["title"], missions.progress_text(m)])
		mission_tracker.text = "\n".join(lines)
	missions.changed.connect(update)
	get_tree().get_first_node_in_group("player_data").changed.connect(update)  # salvage counts
	missions.completed.connect(func(m): flash_message("Mission complete: %s   +%s" % [m["title"], missions.reward_text(m)]))
	update.call()


## Main-quest tracker (top centre), minimap marker and boss health bar.
func bind_quest(quest: Node) -> void:
	_quest = quest
	minimap.quest = quest

	# Objectives column under the minimap (like most RPGs): main quest first,
	# side missions below it. A VBox, so they stack at any text size.
	var column := VBoxContainer.new()
	column.anchor_left = 1.0
	column.anchor_right = 1.0
	column.offset_left = -436
	column.offset_right = -16
	column.offset_top = 324   # (under the minimap's ring)
	column.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	_quest_title = _tracker_label(15, Color(1.0, 0.82, 0.38))
	column.add_child(_quest_title)
	_quest_objective = _tracker_label(17, Color.WHITE)
	column.add_child(_quest_objective)
	var gap := Control.new()
	_quest_gap = gap
	gap.custom_minimum_size = Vector2(0, 10)
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(gap)
	# Move the side-mission tracker into the column, below the main quest.
	mission_tracker.get_parent().remove_child(mission_tracker)
	mission_tracker.set_anchors_preset(Control.PRESET_TOP_LEFT)
	mission_tracker.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(mission_tracker)

	# Boss health bar: top centre, under the system name.
	_boss_bar = BossBar.new()
	_boss_bar.anchor_left = 0.5
	_boss_bar.anchor_right = 0.5
	_boss_bar.offset_left = -300
	_boss_bar.offset_right = 300
	_boss_bar.offset_top = 52   # (below the system's name)
	_boss_bar.offset_bottom = 90
	add_child(_boss_bar)

	var update := func():
		# (the main quest done: no more of it under the minimap - side missions move up)
		_quest_title.text = "" if quest.finished else ("MAIN QUEST  ·  " + quest.chapter_title() if quest.stage >= 0 else "MAIN QUEST")
		_quest_title.visible = _quest_title.text != ""
		_quest_objective.text = "" if quest.finished else quest.objective_text()
		_quest_objective.visible = not quest.finished
		_quest_gap.visible = not quest.finished
	quest.changed.connect(update)
	get_tree().get_first_node_in_group("player_data").changed.connect(update)  # delivery progress
	update.call()
	_apply_text_size()  # the tracker labels were just created


func _process(delta: float) -> void:
	if _boss_bar == null:
		return
	# Show the nearest story boss within range.
	var player := get_tree().get_first_node_in_group("player") as Node2D
	var boss: Node2D = null
	if player:
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.boss and e.is_alive() and e.global_position.distance_to(player.global_position) < 1800.0:
				boss = e
	_boss_bar.boss = boss
	_boss_bar.visible = boss != null
	if boss:
		_boss_bar.queue_redraw()


## Right-aligned, wrapping label for the objectives column.
func _tracker_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	return l


## Event log console in the bottom-left corner. It grows upward with
## bigger text, and its width stops short of the toolbar (GameLog.place).
func _build_left_column() -> void:
	event_log = GameLog.new()
	event_log.anchor_left = 0.0
	event_log.anchor_right = 0.0
	event_log.anchor_top = 1.0
	event_log.anchor_bottom = 1.0
	event_log.offset_left = 16
	event_log.offset_bottom = -16
	event_log.grow_horizontal = Control.GROW_DIRECTION_END
	event_log.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(event_log)


## Show/hide the event log (L key).
func toggle_event_log() -> void:
	event_log.visible = not event_log.visible


## HUD text uses the "HUD" text size setting.
func _apply_text_size() -> void:
	UI.scale_fonts(self, "hud")
	if event_log:
		var k := Settings.font_scale("hud")
		# Grows with the text, but stops short of the toolbar (GameLog.place).
		event_log.place(Vector2(440 * clampf(k, 1.0, 1.45), 220 * clampf(k, 1.0, 1.8)), toolbar)


## Shows the docking prompt for `station` (or hides it when null).
func show_dock_prompt(station: Node2D) -> void:
	dock_prompt.visible = station != null
	if station:
		dock_prompt.text = "Press E to dock at %s" % station.station_name


func flash_message(text: String) -> void:
	message.text = text
	message.modulate.a = 1.0
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(1.8)
	_message_tween.tween_property(message, "modulate:a", 0.0, 0.6)


func _on_health_changed(hull: float, max_hull: float, shields: float, max_shields: float) -> void:
	shield_bar.max_value = max_shields
	shield_bar.value = shields
	shield_value.text = "%d" % ceilf(shields)
	hull_bar.max_value = max_hull
	hull_bar.value = hull
	hull_value.text = "%d" % ceilf(hull)
	# Hull bar goes from green to red as it drops.
	var fill := hull_bar.get_theme_stylebox("fill") as StyleBoxFlat
	fill.bg_color = Color(0.95, 0.25, 0.2).lerp(Color(0.3, 0.9, 0.4), hull / max_hull)


func show_game_over(kills: int) -> void:
	hint.hide()
	dock_prompt.hide()
	toolbar.hide()
	%GameOverStats.text = "Enemies destroyed: %d" % kills
	%LoadButton.disabled = not SaveGame.has_save()
	game_over.show()
	%RestartButton.grab_focus()


## Respawn (was Restart, which started a new game and threw your progress
## away): a new ship at the nearest station, your progress kept (main.respawn).
func _on_restart() -> void:
	var main := get_tree().current_scene
	if main and main.has_method("respawn"):
		main.respawn()
	else:
		SaveGame.pending = {}
		get_tree().change_scene_to_file(GAME_SCENE)


func _on_load() -> void:
	SaveGame.load_slot()


func _on_menu() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


## Big health bar for story bosses (name, shields, hull).
class BossBar extends Control:
	var boss: Node2D

	func _init() -> void:
		mouse_filter = MOUSE_FILTER_IGNORE
		visible = false

	func _draw() -> void:
		if boss == null or not is_instance_valid(boss):
			return
		var font := ThemeDB.fallback_font
		var w := size.x
		draw_string_outline(font, Vector2(0, 14), boss.display_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, Settings.fs("hud", 16), 5, Color.BLACK)
		draw_string(font, Vector2(0, 14), boss.display_name.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, w, Settings.fs("hud", 16), Color(1.0, 0.75, 0.5))
		var y := 20.0
		draw_rect(Rect2(0, y, w, 6), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(0, y, w * clampf(boss.shields / maxf(1.0, boss.max_shields), 0, 1), 6), Color(1.0, 0.6, 0.3))
		draw_rect(Rect2(0, y + 9, w, 9), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(0, y + 9, w * clampf(boss.hull / boss.max_hull, 0, 1), 9), Color(0.95, 0.25, 0.2))
		draw_rect(Rect2(0, y, w, 18), Color(1.0, 0.8, 0.5, 0.5), false, 1.0)
