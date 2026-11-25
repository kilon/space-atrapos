class_name GameLog
extends PanelContainer
## The console (bottom left of the HUD): two tabs, picked by their icons at its
## top - the EVENT LOG (anything in the game posts to it with the static
## helpers, e.g. GameLog.post("Docked at Helios Dock"); rapid repeated events -
## damage, loot - merged per second into one line) and the LOADING console
## (LoadBar: what's loaded, unloaded and made, the memory pool, the work's
## progress bar and the memory map). The loading tab's icon shows the progress
## while you're on the log. L hides the console.

const MAX_LINES := 100
const MERGE_WINDOW := 1.0  # seconds

## Line colours by kind of event.
const COLORS := {
	"info": Color(0.86, 0.78, 0.68),
	"combat": Color(1.0, 0.65, 0.4),
	"danger": Color(1.0, 0.38, 0.32),
	"good": Color(0.5, 1.0, 0.6),
	"loot": Color(1.0, 0.82, 0.38),
	"mission": Color(0.5, 0.76, 1.0),
	"quest": Color(1.0, 0.85, 0.45),
}

var _text: RichTextLabel
## History and clock are static, so the log continues between space and
## planet surfaces. clear_history() starts a fresh log (new game / load).
static var _lines: Array[String] = []
static var _time := 0.0
var _merge_t := 0.0
## Pending merged events: key -> {kind, format, values...}
var _dealt := {}    # target name -> [shields, hull]
var _taken := {}    # attacker name -> [shields, hull]
var _loot := {}     # item name -> amount


# --- Static API ----------------------------------------------------------------

static func clear_history() -> void:
	_lines.clear()
	_time = 0.0


static func _log() -> GameLog:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group("event_log") as GameLog if tree else null


## Post a line. kind: info, combat, danger, good, loot, mission, quest.
static func post(text: String, kind := "info") -> void:
	var l := _log()
	if l:
		l._flush()  # write pending merged lines first, so cause comes before effect
		l._add(text, kind)


## Damage the player dealt to `target` (merged per second).
static func damage_dealt(target: String, shields: float, hull: float) -> void:
	var l := _log()
	if l:
		var d: Array = l._dealt.get(target, [0.0, 0.0])
		l._dealt[target] = [d[0] + shields, d[1] + hull]


## Damage the player took from `attacker` (merged per second).
static func damage_taken(attacker: String, shields: float, hull: float) -> void:
	var l := _log()
	if l:
		var d: Array = l._taken.get(attacker, [0.0, 0.0])
		l._taken[attacker] = [d[0] + shields, d[1] + hull]


## Something collected (merged per second).
static func loot(item: String, amount: int) -> void:
	var l := _log()
	if l:
		l._loot[item] = l._loot.get(item, 0) + amount


# --- Place on screen -----------------------------------------------------------

## Pinned to the bottom-left corner, `want` in size - but never reaching the
## toolbar `bar` (centred along the bottom): its width stops GAP short of the
## bar's left edge. Placed again whenever the bar or the window changes size.
const GAP := 12.0
var _want := Vector2(440, 220)
var _load_bar: LoadBar
var _bar: Control
## The tab shown ("events" or "loading"), kept while the game runs (every scene's console the same).
static var tab := "events"
var _tabs := {}          # tab -> its icon button
var _title: Label

func place(want: Vector2, bar: Control = null) -> void:
	_want = want
	if bar != _bar:
		if _bar and _bar.resized.is_connected(_fit):
			_bar.resized.disconnect(_fit)
		_bar = bar
		if _bar:
			_bar.resized.connect(_fit)
	if is_inside_tree() and not get_viewport().size_changed.is_connected(_fit):
		get_viewport().size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var w := _want.x
	if _bar and _bar.is_inside_tree() and _bar.size.x > 0.0:
		# (in this control's parent's space: the bar's left edge)
		var origin: float = (get_parent() as Control).get_global_rect().position.x if get_parent() is Control else 0.0
		var left: float = _bar.get_global_rect().position.x - origin
		w = minf(w, left - 16.0 - GAP)
	w = maxf(w, 200.0)
	custom_minimum_size = Vector2(w, _want.y)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 16
	offset_right = 16 + w
	offset_bottom = -16
	offset_top = -16 - _want.y
	size = Vector2(w, _want.y)


# --- Console -------------------------------------------------------------------

func _ready() -> void:
	add_to_group("event_log")
	if not SaveGame.travelling and not _built_ahead():
		clear_history()  # new game or loaded save: start a fresh log
	add_to_group("neon_restyle")
	restyle()

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	add_child(v)
	# The tabs: an icon each, then the shown one's name.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	v.add_child(head)
	for t in [["events", "ui_journal", EditorIcons.tip("Event log", "", "What just happened: fights, loot, missions, news.")],
			["loading", "reload", EditorIcons.tip("Loading console", "", "What's loaded, unloaded and made in the background, the memory pool,\nthe work under way and the memory map. The line under this icon: its progress.")]]:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(30, 24)
		EditorIcons.dress_tab(b, t[1], t[2])
		for c in ["icon_normal_color", "icon_pressed_color", "icon_hover_color", "icon_hover_pressed_color", "icon_focus_color"]:
			b.add_theme_color_override(c, Color.WHITE)   # (the theme dims a pressed icon: the shown tab's must be the bright one)
		var on := NeonTheme.box(Color(NeonTheme.CYAN, 0.6), Color(NeonTheme.CYAN, 0.16), 1, 4, 4)
		var off := StyleBoxEmpty.new()
		var hover := NeonTheme.box(Color(NeonTheme.CYAN, 0.3), Color(NeonTheme.CYAN, 0.08), 1, 4, 4)
		b.add_theme_stylebox_override("pressed", on)
		b.add_theme_stylebox_override("hover_pressed", on)
		b.add_theme_stylebox_override("normal", off)
		b.add_theme_stylebox_override("hover", hover)
		b.pressed.connect(show_tab.bind(t[0]))
		if t[0] == "loading":
			b.draw.connect(_draw_load_progress.bind(b))
		head.add_child(b)
		_tabs[t[0]] = b
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 12)
	_title.add_theme_color_override("font_color", Color(NeonTheme.HEAD, 0.8))
	_title.mouse_filter = MOUSE_FILTER_IGNORE
	_title.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(_title)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = true          # vertical scroll bar when there's more to read
	_text.scroll_following = false      # we follow manually (only while at the bottom)
	_text.size_flags_vertical = SIZE_EXPAND_FILL
	_text.mouse_filter = MOUSE_FILTER_STOP  # mouse wheel / dragging scrolls the log
	_style_scrollbar(_text.get_v_scroll_bar())
	_text.add_theme_font_size_override("normal_font_size", 13)
	_text.add_theme_constant_override("line_separation", 1)
	v.add_child(_text)
	# The loading console: the other tab's page (LoadBar).
	_load_bar = LoadBar.new()
	_load_bar.size_flags_vertical = SIZE_EXPAND_FILL
	v.add_child(_load_bar)
	show_tab(tab)
	if _lines.is_empty() and not _built_ahead():
		(func(): post(welcome_line(), "good")).call_deferred()   # (after the scene's _ready: a loaded save's system known)
	else:
		_text.append_text("\n".join(_lines))
		_scroll_to_end.call_deferred()


## In a planet's surface built ahead (hidden, under the space scene): the log's
## history is the game's (static) - that one mustn't clear it or welcome you again.
func _built_ahead() -> bool:
	var n := get_parent()
	while n:
		if n.get("prebuilding") == true and n != get_tree().current_scene:
			return true
		n = n.get_parent()
	return false


## Shows a tab: "events" (the event log) or "loading" (the loading console).
func show_tab(which: String) -> void:
	tab = which if which in ["events", "loading"] else "events"
	_text.visible = tab == "events"
	_load_bar.visible = tab == "loading"
	for t in _tabs:
		(_tabs[t] as Button).button_pressed = t == tab
		(_tabs[t] as Button).modulate = Color.WHITE if t == tab else Color(1, 1, 1, 0.5)
	_title.text = ("EVENT LOG" if tab == "events" else "LOADING") + "   (L to hide)"
	if tab == "events":
		_scroll_to_end.call_deferred()
	else:
		_load_bar.to_end.call_deferred()


## The loading tab's icon: a line under it as long as the work under way is done.
func _draw_load_progress(b: Button) -> void:
	if _load_bar == null or not _load_bar.busy:
		return
	var w := b.size.x - 6.0
	b.draw_rect(Rect2(3, b.size.y - 3.0, w, 2.0), Color(NeonTheme.HEAD, 0.25))
	b.draw_rect(Rect2(3, b.size.y - 3.0, w * clampf(_load_bar._share, 0.0, 1.0), 2.0), NeonTheme.CYAN)


var _busy_was := false
var _share_was := -1.0

func _process(delta: float) -> void:
	if _load_bar and (_load_bar.busy != _busy_was or _load_bar._share != _share_was):
		_busy_was = _load_bar.busy
		_share_was = _load_bar._share
		(_tabs["loading"] as Button).queue_redraw()
	_time += delta
	_merge_t += delta
	if _merge_t >= MERGE_WINDOW:
		_merge_t = 0.0
		_flush()


func _flush() -> void:
	for target in _dealt:
		var d: Array = _dealt[target]
		_add("You dealt %d damage to %s%s" % [roundi(d[0] + d[1]), target, _split(d)], "combat")
	for attacker in _taken:
		var d: Array = _taken[attacker]
		_add("%s hit you for %d%s" % [attacker, roundi(d[0] + d[1]), _split(d)], "danger" if d[1] > 0.0 else "combat")
	for item in _loot:
		_add("+%d %s" % [_loot[item], item], "loot")
	_dealt.clear()
	_taken.clear()
	_loot.clear()


static func _split(d: Array) -> String:
	if d[0] > 0.0 and d[1] > 0.0:
		return "  (shields %d, hull %d)" % [roundi(d[0]), roundi(d[1])]
	return "  (shields)" if d[0] > 0.0 else "  (hull)"


func _add(text: String, kind: String) -> void:
	var col: Color = COLORS.get(kind, COLORS["info"])
	var stamp := "%02d:%02d" % [int(_time / 60.0), int(_time) % 60]
	var line := "[color=#6b7a8f]%s[/color]  [color=#%s]%s[/color]" % [stamp, col.to_html(false), text]
	_lines.append(line)
	if _text == null:
		return
	# Follow new lines only if the reader is already at the bottom; if they
	# scrolled up to read older entries, leave the view where it is.
	var bar := _text.get_v_scroll_bar()
	var at_bottom := bar.value >= bar.max_value - bar.page - 4.0
	if _lines.size() > MAX_LINES:
		_lines.remove_at(0)
		_text.remove_paragraph(0)
	_text.append_text(("\n" if _lines.size() > 1 else "") + line)
	if at_bottom:
		_scroll_to_end.call_deferred()


func _scroll_to_end() -> void:
	var bar := _text.get_v_scroll_bar()
	bar.value = bar.max_value


## Panel style in the GUI palette (NeonTheme).
func restyle() -> void:
	var style := NeonTheme.box(Color(NeonTheme.CYAN, 0.45), Color(NeonTheme.BG, 0.66), 1, 6, 10)
	style.content_margin_left = 10
	style.content_margin_right = 8
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	add_theme_stylebox_override("panel", style)
	for bar in find_children("*", "VScrollBar", true, false):
		_style_scrollbar(bar)


## A visible scroll bar that matches the HUD.
static func _style_scrollbar(bar: VScrollBar) -> void:
	bar.custom_minimum_size.x = 10
	var track := StyleBoxFlat.new()
	track.bg_color = Color(NeonTheme.BG_LIGHT, 0.6)
	track.border_color = Color(NeonTheme.CYAN, 0.2)
	track.set_border_width_all(1)
	var grab := StyleBoxFlat.new()
	grab.bg_color = Color(NeonTheme.CYAN, 0.7)
	grab.corner_radius_top_left = 4
	grab.corner_radius_bottom_right = 4
	grab.corner_detail = 1
	var grab_hover := grab.duplicate()
	grab_hover.bg_color = NeonTheme.PINK
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	bar.add_theme_stylebox_override("grabber", grab)
	bar.add_theme_stylebox_override("grabber_highlight", grab_hover)
	bar.add_theme_stylebox_override("grabber_pressed", grab_hover)


## The log's first line: where you are now (a new game starts in Knossos, the
## Atrapos sector; a save loads wherever it was made).
static func welcome_line() -> String:
	var sys: String = Galaxy.current_system
	var name := str(Galaxy.system(sys).get("name", "")) if Galaxy.systems.has(sys) else ""
	if name == "":
		return "Systems online. Welcome to New Hellas."
	var owner := Galaxy.owner_of(sys)
	var who := (" - " + Galaxy.empire_name(owner)) if owner != "" and owner != "independent" else ""
	if sys == Galaxy.HOME:
		return "Systems online. Welcome to New Hellas - you are in the %s system, its Atrapos sector%s." % [name, who]
	return "Systems online. Welcome to New Hellas - you are in the %s system%s." % [name, who]


## The console's LOADING tab: the history of what's been loaded, unloaded and
## made (AssetPool.events: each sprite, each planet's plan and ground chunks,
## each piece of a solar system) with a scroll bar like the log's - kept for the
## whole session, there to look through after the loading's done; the memory
## pool's total (AssetPool.summary); a progress bar (a planet being built, the
## system streaming in, the ground round you on a planet, the pictures); and the
## memory map. It keeps up with the work while the other tab is shown (the
## tab's icon shows the progress).
class LoadBar extends VBoxContainer:
	const BAR_H := 18.0
	const POOL_H := 16.0
	const MAP_H := 12.0
	const MAX_LINES := 1000
	var busy := false
	var _share := 0.0
	var _text := ""
	var _t := 0.0
	var _seen := 0
	var _lines := 0
	var _log: Lines
	var _pool: Control
	var _bar: Control
	var _map: MemMap
	var _pool_text := ""

	func _ready() -> void:
		add_theme_constant_override("separation", 3)
		mouse_filter = MOUSE_FILTER_STOP
		_log = Lines.new()
		_log.custom_minimum_size.y = 30.0
		_log.size_flags_vertical = SIZE_EXPAND_FILL
		add_child(_log)
		_pool = Control.new()
		_pool.custom_minimum_size.y = POOL_H
		_pool.mouse_filter = MOUSE_FILTER_IGNORE
		_pool.draw.connect(_draw_pool)
		add_child(_pool)
		_bar = Control.new()
		_bar.custom_minimum_size.y = BAR_H
		_bar.mouse_filter = MOUSE_FILTER_IGNORE
		_bar.draw.connect(_draw_bar)
		add_child(_bar)
		# The memory map: the pool's room, by kind of asset (hover: what's in each).
		_map = MemMap.new()
		_map.custom_minimum_size.y = MAP_H
		add_child(_map)
		# The session's history so far (the console of the scene before had it too).
		_take_events(AssetPool.events.size())
		_seen = AssetPool.serial
		_fit_text()
		_log.to_end.call_deferred()

	func to_end() -> void:
		if _log:
			_log.to_end()

	## Its text's size: the event log's (13 at the HUD's text size - Settings).
	static func fs() -> int:
		return Settings.fs("hud", 13)

	var _fs_was := 0

	## The rows and bars sized to the text (again when the HUD's text size changes).
	func _fit_text() -> void:
		var f := fs()
		if f == _fs_was:
			return
		_fs_was = f
		_pool.custom_minimum_size.y = f + 4.0
		_bar.custom_minimum_size.y = f + 6.0
		_map.custom_minimum_size.y = maxf(MAP_H, f * 0.8)
		_log.queue_redraw()
		_log._fit_bar()
		_pool.queue_redraw()
		_bar.queue_redraw()

	## The newest `n` notes added to the history.
	func _take_events(n: int) -> void:
		var ev: Array = AssetPool.events
		var from := maxi(0, ev.size() - n)
		var rows: Array = []
		for k in range(from, ev.size()):
			var e: Array = ev[k]
			var col := Color(1.0, 0.72, 0.35) if e[2] == "unload" else (Color(0.62, 0.82, 1.0) if e[2] == "load" else Color(0.92, 0.95, 1.0))
			var t := float(e[0])
			rows.append(["%02d:%02d" % [int(t / 60.0), int(t) % 60], str(e[1]), col])
		_log.add(rows)

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0:
			return
		_t = 0.25
		_fit_text()
		if AssetPool.serial != _seen:
			_take_events(AssetPool.serial - _seen)
			_seen = AssetPool.serial
		var was := [busy, _share, _text, _pool_text]
		busy = false
		# A planet's surface being built (ahead, or for the landing under way)
		# comes first - what it's doing; then the system streaming in; then the
		# ground being made round you on a planet; else the pictures loading.
		var scene := get_tree().current_scene
		var pre = null
		for k in ["_landing_surface", "_prebuilt"]:
			var n = scene.get(k) if scene else null
			if n != null and is_instance_valid(n) and n.get("is_built") == false:
				pre = n
				break
		if scene and scene.has_method("stream_progress"):
			var c: Vector2i = scene.stream_progress()
			if c.x < c.y:
				busy = true
				_share = float(c.x) / maxf(1.0, c.y)
				_text = "%s system: streaming in  (%d / %d pieces)" % [str(Galaxy.SYSTEMS[Galaxy.current_system]["name"]), c.x, c.y]
		if not busy and pre != null:
			busy = true
			_share = float(pre.build_progress)
			var pname := str(Planets.get_planet(str(pre.planet_id)).get("name", ""))
			_text = "%s: %s  %d%%" % [pname, str(pre.build_stage) if str(pre.build_stage) != "" else "preparing", roundi(_share * 100.0)]
		if not busy and scene and scene.has_method("near_progress") and str(scene.get("build_stage")) != "":
			var c: Vector2i = scene.near_progress()
			if c.x < c.y:
				busy = true
				_share = float(c.x) / maxf(1.0, c.y)
				_text = "%s: making the ground round you  (%d / %d chunks)" % [str(scene.pdata.get("name", "")), c.x, c.y]
		if not busy and not ProcArt.all_ready():
			busy = true
			_share = ProcArt.overall()
			var c: Vector2i = ProcArt.counts()
			_text = "Loading %s  (%d / %d)" % [ProcArt.stage, c.x, c.y] if not ProcArt.ready_done or ProcArt.stage != "Ready" else "Loading the game's scenes"
		if not busy:
			_share = 1.0
			_text = "All loaded"
		_pool_text = AssetPool.summary()
		if [busy, _share, _text, _pool_text] != was:
			_bar.queue_redraw()
			_pool.queue_redraw()

	func _draw_bar() -> void:
		var r := Rect2(Vector2.ZERO, _bar.size)
		var font := get_theme_default_font()
		_bar.draw_rect(r, Color(0, 0, 0, 0.35))
		_bar.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(_share, 0.0, 1.0), r.size.y)), Color(NeonTheme.CYAN, 0.55 if busy else 0.25))
		_bar.draw_rect(r, Color(NeonTheme.HEAD, 0.5), false, 1.0)
		_bar.draw_string(font, Vector2(5, (r.size.y + fs() * 0.72) / 2.0), _text, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10.0, fs(), Color(1, 1, 1, 0.92))

	func _draw_pool() -> void:
		var w := _pool.size.x
		var font := get_theme_default_font()
		# A thin gauge of used / budget under its line (orange past 90%).
		var k := clampf(float(AssetPool.used) / maxf(1.0, AssetPool.budget), 0.0, 1.0)
		var h := _pool.size.y
		_pool.draw_rect(Rect2(0, h - 2.0, w, 2.0), Color(NeonTheme.HEAD, 0.15))
		_pool.draw_rect(Rect2(0, h - 2.0, w * k, 2.0), Color(1.0, 0.72, 0.35, 0.8) if k > 0.9 else Color(NeonTheme.HEAD, 0.6))
		_pool.draw_string(font, Vector2(0, h - 4.0), _pool_text, HORIZONTAL_ALIGNMENT_LEFT, w, fs(), Color(NeonTheme.HEAD, 0.95))


## The memory pool's map (the loading console, under its bar): its whole room
## (AssetPool.budget) as a strip, each kind of asset an area as wide as the
## memory it takes, in its colour (AssetPool.KINDS), the free room dark. Over
## an area: a tooltip - how many, how much, its share, its biggest assets with
## their sizes and priorities.
class MemMap extends Control:
	var _parts: Array = []
	var _t := 0.0

	func _ready() -> void:
		mouse_filter = MOUSE_FILTER_STOP
		tooltip_text = " "   # (tooltips on: the text comes from _get_tooltip)

	func _process(delta: float) -> void:
		_t -= delta
		if _t > 0.0 or not is_visible_in_tree():
			return
		_t = 0.5
		_parts = AssetPool.breakdown()
		queue_redraw()

	## [kind's dictionary, x0, x1] along the strip.
	func _spans() -> Array:
		var out := []
		var room := maxf(1.0, float(maxi(AssetPool.budget, AssetPool.used)))
		var x := 0.0
		for d in _parts:
			var w: float = size.x * float(d["bytes"]) / room
			out.append([d, x, x + w])
			x += w
		return out

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0, 0, 0, 0.45))
		var hot := get_local_mouse_position() if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()) else Vector2(-1, -1)
		for sp in _spans():
			var c: Color = sp[0]["color"]
			var box := Rect2(sp[1], 0.0, maxf(1.0, sp[2] - sp[1]), size.y)
			draw_rect(box, c.lightened(0.25) if box.has_point(hot) else Color(c, 0.85))
			if box.size.x > 3.0:
				draw_line(Vector2(box.end.x, 0), Vector2(box.end.x, size.y), Color(0, 0, 0, 0.6), 1.0)
		draw_rect(r, Color(NeonTheme.HEAD, 0.5), false, 1.0)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseMotion:
			queue_redraw()

	func _get_tooltip(at: Vector2) -> String:
		for sp in _spans():
			if at.x >= sp[1] and at.x < sp[2]:
				var d: Dictionary = sp[0]
				var lines := PackedStringArray()
				lines.append("%s - %d assets, %s  (%d%% of the pool's room)" % [d["name"], d["count"], AssetPool.mb(d["bytes"]),
					roundi(100.0 * d["bytes"] / maxf(1.0, AssetPool.budget))])
				lines.append("The biggest (size, priority - the least used are unloaded first if the pool runs out of room):")
				for it in d["top"]:
					lines.append("   %s   %s   priority %.1f" % [it[0], AssetPool.mb(it[1]), it[2]])
				return "\n".join(lines)
		return "Free room: %s of %s  (the pool keeps twice what the game usually needs)" % [
			AssetPool.mb(maxi(0, AssetPool.budget - AssetPool.used)), AssetPool.mb(AssetPool.budget)]


## The loading console's history: lines kept in a list, only the rows in view
## drawn (a label holding 1000 lines laid all its text out again whenever lines
## came and old ones went: a 45 ms frame every second while planets were built).
## A scroll bar (styled like the event log's) and the mouse wheel move it; it
## follows new lines only while you're at the bottom.
class Lines extends Control:
	const MAX := 1000
	var rows: Array = []   # [stamp, text, colour]
	var _bar: VScrollBar

	func _ready() -> void:
		clip_contents = true
		mouse_filter = MOUSE_FILTER_STOP
		_bar = VScrollBar.new()
		GameLog._style_scrollbar(_bar)
		_bar.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		_bar.offset_left = -10
		_bar.step = 1.0
		_bar.value_changed.connect(func(_v): queue_redraw())
		add_child(_bar)
		resized.connect(_fit_bar)

	## A row's height: the text's size (the HUD's) and a little.
	func _row() -> float:
		return LoadBar.fs() + 3.0

	func _visible_rows() -> int:
		return maxi(1, floori(size.y / _row()))

	func _fit_bar() -> void:
		_bar.max_value = rows.size()
		_bar.page = _visible_rows()
		_bar.visible = rows.size() > _visible_rows()
		queue_redraw()

	func at_end() -> bool:
		return _bar.value >= _bar.max_value - _bar.page - 0.5

	func to_end() -> void:
		_bar.value = maxf(0.0, _bar.max_value - _bar.page)
		queue_redraw()

	func add(new_rows: Array) -> void:
		if new_rows.is_empty():
			return
		var follow := at_end()
		rows.append_array(new_rows)
		var cut := rows.size() - MAX
		if cut > 0:
			rows = rows.slice(cut)
			if not follow:
				_bar.value = maxf(0.0, _bar.value - cut)   # (the lines you're reading stay in view)
		_fit_bar()
		if follow:
			to_end()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				_bar.value -= 3
				accept_event()
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_bar.value += 3
				accept_event()

	func _draw() -> void:
		var font := get_theme_default_font()
		var first := int(_bar.value)
		var w := size.x - (14.0 if _bar.visible else 2.0)
		var f := LoadBar.fs()
		var row := _row()
		var gap := font.get_string_size("00:00  ", HORIZONTAL_ALIGNMENT_LEFT, -1, f).x
		for i in _visible_rows():
			var k := first + i
			if k >= rows.size():
				break
			var r: Array = rows[k]
			var y := i * row + row - 3.0
			draw_string(font, Vector2(0, y), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, f, Color(0.42, 0.48, 0.56))
			draw_string(font, Vector2(gap, y), r[1], HORIZONTAL_ALIGNMENT_LEFT, w - gap, f, r[2])

