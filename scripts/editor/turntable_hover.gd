class_name TurntableHover
extends Node
## A list's pictures turning: the item under the mouse cycles through its turntable
## (its frames - MeshThumbs.frames()) at FPS, by the clock; put back to its first
## frame when the mouse leaves it. One item at a time: an icon swapped a few times a
## second, nothing while the mouse is elsewhere.
##   TurntableHover.attach(item_list, func(meta) -> Array: return thumbs.frames(meta))

const FPS := 5.0   # (a slow turn: about five seconds round)

var list: ItemList
var frames_of: Callable
var _item := -1
var _shown := -1
var _t := 0.0


static func attach(l: ItemList, frames: Callable) -> TurntableHover:
	var h := TurntableHover.new()
	h.list = l
	h.frames_of = frames
	h.name = "TurntableHover"
	l.add_child(h)
	l.mouse_exited.connect(h._leave)
	return h


func _process(dt: float) -> void:
	if list == null or not list.is_visible_in_tree():
		return
	var at := list.get_local_mouse_position()
	var i := list.get_item_at_position(at, true) if Rect2(Vector2.ZERO, list.size).has_point(at) else -1
	if i != _item:
		_leave()
		_item = i
		_t = 0.0
	if _item < 0 or _item >= list.item_count:
		return
	var f: Array = frames_of.call(list.get_item_metadata(_item))
	if f.is_empty():
		return
	_t += dt
	var k := int(_t * FPS) % f.size()
	if k != _shown:
		_shown = k
		list.set_item_icon(_item, f[k])


func _leave() -> void:
	if _item >= 0 and _item < list.item_count:
		var f: Array = frames_of.call(list.get_item_metadata(_item))
		if not f.is_empty():
			list.set_item_icon(_item, f[0])
	_item = -1
	_shown = -1
