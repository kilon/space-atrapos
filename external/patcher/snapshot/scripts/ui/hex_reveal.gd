class_name HexReveal
extends Node
## A curtain of hexagon tiles that a full-screen menu opens and closes with
## (the Automaton, the Field Computer). Opening (play): the tiles grow
## from nothing - the ones in the middle first, then outward to both sides
## like curtains drawn apart, each a little at random - and the menu shows
## only where they've opened, each tile's rim glowing as it does. Closing
## (play(menu, true, hide)): the same backwards, a little quicker, then the
## menu hides; Tab again meanwhile turns it round where it is.
## How: while it plays, the menu's material is the curtain shader
## (shaders/hex_reveal.gdshader) and every part of the menu uses it
## (use_parent_material) - each pixel shows only if its tile has opened; the
## game behind shows through the rest. Done, every part gets its own look
## back: an open menu costs nothing more. (Headless - the tests - menus open
## and close at once.)

const R := 56.0                  # a tile's radius (corner to centre), px
const SPREAD := 0.36             # s: from the middle tiles to the edge ones
const JITTER := 0.08             # s: each tile's own bit of randomness
const GROW := 0.26               # s: one tile, nothing to full size
const REVEAL_TIME := SPREAD + JITTER + GROW
const CLOSE_SPEED := 1.4         # closing this many times quicker

var _menu: Control
var _reverse := false
var _done: Callable
var _t := 0.0
var _parts: Array = []           # the menu's parts that use its material meanwhile
var _old_material: Material
var _blocker: Control            # (closing: clicks don't reach the menu)


## Plays the curtain on `menu`: opening (it was just shown), or `reverse` -
## closing, then `done` (hide it). Already playing: turns round where it is.
static func play(menu: Control, reverse := false, done := Callable()) -> void:
	if DisplayServer.get_name() == "headless":
		if done.is_valid():
			done.call()
		return
	var t := 0.0
	var old := menu.get_node_or_null("HexReveal") as HexReveal
	if old:
		t = REVEAL_TIME - old._t if old._reverse != reverse else old._t   # (the same tiles open)
		old.finish(false)
	var h := HexReveal.new()
	h.name = "HexReveal"
	h._menu = menu
	h._reverse = reverse
	h._done = done
	h._t = t
	menu.add_child(h)


## Ends `menu`'s curtain now (its menu whole - or hidden, if it was closing).
static func stop(menu: Control) -> void:
	var h := menu.get_node_or_null("HexReveal") as HexReveal
	if h:
		h.finish(true)


## (Playing on `menu`? closing?)
static func running(menu: Control) -> bool:
	return menu.get_node_or_null("HexReveal") != null


static func closing(menu: Control) -> bool:
	var h := menu.get_node_or_null("HexReveal") as HexReveal
	return h != null and h._reverse


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/hex_reveal.gdshader")
	sm.set_shader_parameter("r", R)
	sm.set_shader_parameter("spread", SPREAD)
	sm.set_shader_parameter("jitter", JITTER)
	sm.set_shader_parameter("grow", GROW)
	sm.set_shader_parameter("edge", NeonTheme.HEAD)
	sm.set_shader_parameter("size", _menu.get_viewport_rect().size)
	_old_material = _menu.material
	_menu.material = sm
	var stack: Array = _menu.get_children()
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is CanvasItem and not n.use_parent_material and n.material == null:
			n.use_parent_material = true
			_parts.append(n)
	if _reverse:
		_blocker = Control.new()
		_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
		_menu.add_child(_blocker)
		_blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_update()


func _update() -> void:
	(_menu.material as ShaderMaterial).set_shader_parameter("t", REVEAL_TIME - _t if _reverse else _t)


func _process(delta: float) -> void:
	if is_queued_for_deletion():
		return   # (finished: the menu has its own material back)
	_t += delta * (CLOSE_SPEED if _reverse else 1.0)
	if _t >= REVEAL_TIME:
		finish(true)
		return
	_update()


## Ends it: every part its own look back; closing - `call_done`: the menu hidden.
func finish(call_done := true) -> void:
	for n in _parts:
		if is_instance_valid(n):
			n.use_parent_material = false
	_parts.clear()
	if is_instance_valid(_menu) and _menu.material is ShaderMaterial and (_menu.material as ShaderMaterial).shader == preload("res://shaders/hex_reveal.gdshader"):
		_menu.material = _old_material
	if is_instance_valid(_blocker):
		_blocker.queue_free()
	name = "HexReveal_done"
	queue_free()
	if call_done and _done.is_valid():
		_done.call()
