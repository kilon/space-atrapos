class_name TouchControls
extends CanvasLayer
## On a touch screen (a phone or a tablet - the web build): what the mouse and
## the keyboard do, by hand (autoload "Touch"). A tap is already the left
## button (Godot's mouse emulation: fly there, walk there, hold to keep going,
## hold on a rock to cut it). On top of that:
##   - a two-finger tap: the right button where the first finger was (scan a
##     rock, the probe scanner in empty space, the context menu on foot);
##   - a pinch: zoom (the mouse wheel);
##   - two columns of buttons by the left edge for the keys: the menu (Esc), the
##     computer (Tab), the map (M), attack the nearest enemy (F), dock / use
##     (E), zoom in and out - between the status bars and the event log.
## Shown only with a touch screen (or `forced`: tests), in play - space and a
## planet's surface - and not while a menu covers the game (they have their
## own Close buttons).

const BUTTONS := [["MENU", "pause"], ["COMPUTER", "computer"], ["MAP", "sector_map"], ["ATTACK", "attack"], ["DOCK", "dock"]]
## Pixels a pinch has to open or close by for one step of zoom.
const PINCH_STEP := 48.0
## A two-finger tap: both down for less than this, neither moving more than TAP_SLOP.
const TAP_TIME := 0.35
const TAP_SLOP := 24.0

var forced := false
var _col: GridContainer
var _touches := {}     # finger index -> position (the viewport's)
var _starts := {}      # finger index -> [position, time]
var _pinch_d := 0.0
var _two_tap := false
var _check := 0.0


func _ready() -> void:
	layer = 60   # (over the HUD; the menus hide it)
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Two columns by the left edge, between the status bars and the event log
	# (the right side has the tutorial's icon and the missions).
	_col = GridContainer.new()
	_col.name = "Buttons"
	_col.columns = 2
	_col.add_theme_constant_override("h_separation", 10)
	_col.add_theme_constant_override("v_separation", 10)
	_col.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_col.grow_horizontal = Control.GROW_DIRECTION_END
	_col.grow_vertical = Control.GROW_DIRECTION_BOTH
	_col.offset_left = 18
	_col.modulate = Color(1, 1, 1, 0.8)
	for b in BUTTONS:
		_col.add_child(_button(b[0], _act.bind(b[1])))
	_col.add_child(_button("ZOOM +", _wheel.bind(MOUSE_BUTTON_WHEEL_UP)))
	_col.add_child(_button("ZOOM -", _wheel.bind(MOUSE_BUTTON_WHEEL_DOWN)))
	add_child(_col)
	visible = false


func _button(text: String, cb: Callable, min_size := Vector2(154, 64)) -> Button:
	var b := UI.button(text, cb, 20)
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b


## A touch screen here? (the web build on a phone or a tablet; a laptop's touch screen too)
static func available() -> bool:
	return DisplayServer.is_touchscreen_available()


func _process(delta: float) -> void:
	_check -= delta
	if _check > 0.0:
		return
	_check = 0.25
	visible = (forced or available()) and in_play() and Keybinds.active_menu() == null and not UI.esc_menu_open()


## Space or a planet's surface (not the title screen, Talos, a loading screen).
func in_play() -> bool:
	var s := get_tree().current_scene
	if s == null or s.get_script() == null:
		return false
	var p: String = s.get_script().resource_path
	return p.ends_with("/main.gd") or p.ends_with("/planet_surface.gd")


## A key's action, pressed and let go.
func _act(id: String) -> void:
	for down in [true, false]:
		var e := InputEventAction.new()
		e.action = id
		e.pressed = down
		Input.parse_input_event(e)


## The mouse wheel at the middle of the screen (zoom).
func _wheel(button: MouseButton) -> void:
	var vp := get_viewport()
	_click(vp.get_visible_rect().size * 0.5, button)


## A mouse button pressed and let go at `at` (the viewport's coordinates).
func _click(at: Vector2, button: MouseButton) -> void:
	var win := get_viewport().get_final_transform() * at   # (events come in as the window's)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = down
		e.position = win
		e.global_position = win
		Input.parse_input_event(e)


func _input(event: InputEvent) -> void:
	if not (forced or available()):
		return
	if event is InputEventScreenTouch:
		var now := Time.get_ticks_msec() / 1000.0
		if event.pressed:
			_touches[event.index] = event.position
			_starts[event.index] = [event.position, now]
			if _touches.size() == 2:
				_pinch_d = _span()
				_two_tap = true
			elif _touches.size() > 2:
				_two_tap = false
		else:
			if _two_tap and _touches.size() == 2:
				var first: int = _touches.keys().min()
				var quick := true
				for i in _starts:
					quick = quick and now - float(_starts[i][1]) <= TAP_TIME
				if quick:
					_click(_starts[first][0], MOUSE_BUTTON_RIGHT)
			_two_tap = false
			_touches.erase(event.index)
			_starts.erase(event.index)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _starts.has(event.index) and event.position.distance_to(_starts[event.index][0]) > TAP_SLOP:
			_two_tap = false
		if _touches.size() == 2:
			var d := _span()
			if absf(d - _pinch_d) >= PINCH_STEP:
				var mid: Vector2 = (_touches.values()[0] + _touches.values()[1]) * 0.5
				_click(mid, MOUSE_BUTTON_WHEEL_UP if d > _pinch_d else MOUSE_BUTTON_WHEEL_DOWN)
				_pinch_d = d
				_two_tap = false


func _span() -> float:
	var v := _touches.values()
	return (v[0] as Vector2).distance_to(v[1]) if v.size() >= 2 else 0.0
