class_name ItemSlot
extends Control
## A square slot showing an item icon and count. Used in the inventory and
## station screens. Drag and drop: a slot with a `payload` can be dragged (its
## icon follows the mouse); a slot with `on_drop` takes drops (on_drop.call(
## payload) - true if it took it; `accepts` decides what it will take).
## A click is a press and release without a drag.

signal hovered(id: String)
signal clicked(id: String)

var item_id := ""
var count := 0
var dim := false
var show_count := true
var payload := {}                   # what dragging this slot carries ({} - not draggable)
var on_drop := Callable()           # (payload) -> bool: a drop onto this slot
var accepts := Callable()           # (payload) -> bool: will it take this drop? (default: anything)
var _hover := false
var _pressed := false


static func make(id: String, n := 0, size := 64.0, is_dim := false) -> ItemSlot:
	var s := ItemSlot.new()
	s.item_id = id
	s.count = n
	s.dim = is_dim
	s.custom_minimum_size = Vector2(size, size)
	return s


func _ready() -> void:
	add_to_group("item_slots")   # (redrawn when the icons' textures are baked: Items.icon_texture)
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_entered.connect(func(): _hover = true; hovered.emit(item_id); queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
		elif _pressed:
			_pressed = false
			if not get_viewport().gui_is_dragging():
				clicked.emit(item_id)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	_pressed = false
	if payload.is_empty() or item_id == "":
		return null
	var ghost := ItemSlot.make(item_id, count, size.x * 0.9)
	ghost.modulate = Color(1, 1, 1, 0.8)
	var holder := Control.new()
	holder.add_child(ghost)
	ghost.position = -ghost.custom_minimum_size * 0.5
	set_drag_preview(holder)
	return payload


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not on_drop.is_valid() or not data is Dictionary:
		return false
	return accepts.call(data) if accepts.is_valid() else true


func _drop_data(_at: Vector2, data: Variant) -> void:
	on_drop.call(data)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(NeonTheme.BG_LIGHT, 0.95))
	var border := Color(NeonTheme.HEAD, 0.9) if _hover and item_id != "" else Color(NeonTheme.CYAN, 0.35)
	draw_rect(r, border, false, 1.5)
	if item_id == "":
		return
	var pad := size.x * 0.16
	var ir := Rect2(Vector2(pad, pad * 0.8), size - Vector2(pad, pad) * 2.0)
	var tex := Items.icon_texture(item_id, dim)
	if tex:
		draw_texture_rect(tex, ir, false)   # (baked once: one draw call)
	else:
		Items.draw_icon(self, item_id, ir, dim)
	if show_count and count > 1:
		var font := ThemeDB.fallback_font
		var text := str(count)
		draw_string_outline(font, Vector2(0, size.y - 5), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, Settings.fs("menu", 14), 4, Color.BLACK)
		draw_string(font, Vector2(0, size.y - 5), text, HORIZONTAL_ALIGNMENT_RIGHT, size.x - 5, Settings.fs("menu", 14), Color.WHITE)
