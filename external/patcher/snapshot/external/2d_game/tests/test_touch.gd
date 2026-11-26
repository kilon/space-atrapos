extends TestCase
## Playing by touch (TouchControls, autoload "Touch": the web build on a phone
## or a tablet): the buttons for the keys, a pinch to zoom, a two-finger tap
## for the right button - and the web build's own bits (Settings.on_web).

var _main: Node
var _was_scene: Node


func setup() -> void:
	Galaxy.new_game(false)
	SaveGame.travelling = false
	_was_scene = tree.current_scene


func teardown() -> void:
	Touch.forced = false
	Touch._touches.clear()
	Touch._starts.clear()
	tree.current_scene = _was_scene
	if is_instance_valid(_main):
		_main.queue_free()
	SaveGame.pending = {}


func _space() -> void:
	Galaxy.current_system = Galaxy.HOME
	_main = load("res://main.tscn").instantiate()
	tree.root.add_child(_main)
	tree.current_scene = _main
	for i in 40:
		await tree.process_frame


func _show() -> void:
	Touch._check = 0.0
	await tree.process_frame
	await tree.process_frame


func _touch(index: int, at: Vector2, down: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = at
	e.pressed = down
	Touch._input(e)


func _drag(index: int, at: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = at
	Touch._input(e)


func test_buttons_in_play() -> void:
	await _show()
	check(not Touch.visible, "the title screen / no touch screen: hidden")
	await _space()
	Touch.forced = true
	await _show()
	check(Touch.visible, "in space with a touch screen: shown")
	var labels: Array = Touch._col.get_children().filter(func(c): return c is Button).map(func(b): return b.text)
	check(labels.has("MENU") and labels.has("COMPUTER") and labels.has("MAP") and labels.has("ATTACK"), "the keys as buttons (%s)" % str(labels))
	# The COMPUTER button: Tab - the Ship Computer opens, and the buttons step aside.
	Touch._act("computer")
	for i in 10:
		await tree.process_frame
	check(_main.ship_menu.visible, "COMPUTER opens the Ship Computer")
	await _show()
	check(not Touch.visible, "hidden while a menu covers the game")
	_main.ship_menu.hide()
	await _show()
	check(Touch.visible, "back when it's closed")


func test_pinch_and_two_finger_tap() -> void:
	await _space()
	Touch.forced = true
	# The zoom buttons and a pinch: the mouse wheel.
	_main._zoom = 1.0
	Touch._wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await tree.process_frame
	check(_main._zoom < 1.0, "the - button zooms out (%.2f)" % _main._zoom)
	var z: float = _main._zoom
	_touch(0, Vector2(800, 500), true)
	_touch(1, Vector2(900, 500), true)
	_drag(1, Vector2(1000, 500))
	await tree.process_frame
	check(_main._zoom > z, "fingers apart: zoom in (%.2f -> %.2f)" % [z, _main._zoom])
	_touch(1, Vector2(1000, 500), false)
	_touch(0, Vector2(800, 500), false)
	# A quick two-finger tap in empty space: the right button - the probe scanner.
	_main.player_data.add_equipment("probe_scanner")
	_touch(0, Vector2(700, 350), true)   # (empty space: clear of the HUD's panels)
	_touch(1, Vector2(760, 370), true)
	_touch(1, Vector2(760, 370), false)
	_touch(0, Vector2(700, 350), false)
	for i in 10:
		await tree.process_frame
	check(_main.ship_menu.visible and _main.ship_menu.current == _main.ship_menu.MAP_TAB, "a two-finger tap: the right button (the probe scanner's map)")


func test_web_bits() -> void:
	check(not Settings.on_web(), "this isn't a web build")
	check(Settings.PHONE_TEXT["hud"] > 1.0, "phones start with bigger text")
	check(AnatomyArt.path("muscles") == "res://art/anatomy/muscles.png", "the full anatomy pictures here")
	check(ResourceLoader.exists("res://art/anatomy/web/muscles.png"), "the web build's half-size ones exist")
	check_eq(AnatomyArt.region(Rect2(100, 50, 400, 200)), Rect2(100, 50, 400, 200), "no scaling with the full pictures")
