extends Control
## Bottom toolbar: Inventory.TOOLBAR_SLOTS (9) slots you fill yourself
## (PlayerData.toolbar) with weapons and ship systems - hover one in the Ship
## Computer's inventory and press 1-9; right-click a slot to empty it. Shows
## the active weapon, ammo / item counts, cooldowns and locked (not yet bought)
## slots. Click a slot or press its number key.

signal slot_pressed(index: int)

const SLOT := 70.0
const GAP := 8.0

var ship: Node2D
var data: Node
var _hover := -1
var _press := -1                    # the slot pressed (a click is its release, not a drag)


func _ready() -> void:
	var count := Inventory.TOOLBAR_SLOTS
	custom_minimum_size = Vector2(count * SLOT + (count - 1) * GAP, SLOT)
	mouse_exited.connect(func(): _hover = -1)


func _process(_delta: float) -> void:
	if UI.redraw_due(self, 30.0):   # (cooldowns, counts: 30 a second is plenty)
		queue_redraw()


func slot_rect(i: int) -> Rect2:
	return Rect2(i * (SLOT + GAP), 0, SLOT, SLOT)


func _slot_at(pos: Vector2) -> int:
	for i in Inventory.TOOLBAR_SLOTS:
		if slot_rect(i).has_point(pos):
			return i
	return -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _slot_at(event.position)
	elif event is InputEventMouseButton:
		var i := _slot_at(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press = i
			elif i >= 0 and i == _press and not get_viewport().gui_is_dragging():
				slot_pressed.emit(i)
			if not event.pressed:
				_press = -1
		elif event.pressed and i >= 0 and event.button_index == MOUSE_BUTTON_RIGHT and data:
			data.toolbar[i] = ""   # (emptied)
		accept_event()


## Drag a slot onto another (they swap), or something usable onto a slot from
## the Ship Computer's inventory (Inventory.toolbar_drop).
func _get_drag_data(at: Vector2) -> Variant:
	var i := _slot_at(at)
	_press = -1
	if i < 0 or data == null or str(data.toolbar[i]) == "":
		return null
	var ghost := ItemSlot.make(data.toolbar[i], 0, SLOT * 0.8)
	ghost.modulate = Color(1, 1, 1, 0.8)
	var holder := Control.new()
	holder.add_child(ghost)
	ghost.position = -ghost.custom_minimum_size * 0.5
	set_drag_preview(holder)
	return {"src": "toolbar", "which": "ship", "index": i, "id": data.toolbar[i]}


func _can_drop_data(at: Vector2, d: Variant) -> bool:
	return data != null and d is Dictionary and _slot_at(at) >= 0 and Inventory.toolbar_accepts(d, false)


func _drop_data(at: Vector2, d: Variant) -> void:
	Inventory.toolbar_drop(data.toolbar, _slot_at(at), d, false)
	queue_redraw()


## The slot's {type, id} ({} when empty).
func slot_at(i: int) -> Dictionary:
	if data == null or i < 0 or i >= data.toolbar.size():
		return {}
	var id: String = data.toolbar[i]
	if Items.WEAPONS.has(id):
		return {"type": "weapon", "id": id}
	if Items.SYSTEMS.has(id):
		return {"type": "system", "id": id}
	return {}


func _draw() -> void:
	if ship == null or data == null:
		return
	var font := ThemeDB.fallback_font

	for i in Inventory.TOOLBAR_SLOTS:
		var slot := slot_at(i)
		var r := slot_rect(i)
		if slot.is_empty():   # an empty slot: dim, its number
			draw_rect(r, Color(NeonTheme.BG, 0.55))
			draw_rect(r, Color(NeonTheme.CYAN.darkened(0.3), 0.35 if i != _hover else 0.8), false, 1.5)
			_text(font, r, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 17, 14, Color(NeonTheme.TEXT, 0.6))
			continue
		var id: String = slot["id"]
		var is_weapon: bool = slot["type"] == "weapon"
		var owned := _owned(slot)
		var active: bool = is_weapon and owned and ship.weapon_on(id)   # (a weapon kind: lit while switched on)

		# Background + border.
		# The GUI palette (NeonTheme).
		draw_rect(r, Color(NeonTheme.BG, 0.88))
		var border := Color(NeonTheme.CYAN.darkened(0.3), 0.7)
		if active:
			border = NeonTheme.CYAN
		elif i == _hover:
			border = Color(NeonTheme.CYAN.lightened(0.3), 0.9)
		draw_rect(r, border, false, 3.0 if active else 1.5)
		if active:
			draw_rect(r.grow(-3), Color(NeonTheme.CYAN, 0.1))

		# Icon.
		var usable := owned and _has_supply(slot)
		Items.draw_icon(self, id, r.grow(-16), not usable)

		# Cooldown overlay (systems): dark curtain shrinking upward + seconds.
		if not is_weapon:
			var left: float = ship.cooldown_left(id)
			if left > 0.0:
				var frac: float = left / ship.system_cooldown(id)
				draw_rect(Rect2(r.position + Vector2(0, r.size.y * (1.0 - frac)), Vector2(r.size.x, r.size.y * frac)),
						Color(0, 0, 0, 0.6))
				_text(font, r, "%.0f" % ceilf(left), HORIZONTAL_ALIGNMENT_CENTER, r.size.y / 2.0 + 8, 22, Color.WHITE)
			if id == "afterburner" and ship.boost_time > 0.0:
				draw_rect(r.grow(-2), Color(1.0, 0.6, 0.2, 0.25))

		# Hotkey number.
		_text(font, r, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 17, 14, NeonTheme.TEXT)

		# Ammo / item count.
		var count_text := ""
		if id == "missile_launcher" and owned:
			count_text = str(data.count("missile"))
		elif id == "repair_kit":
			count_text = str(data.count("repair_kit"))
		if count_text != "":
			var col := Color.WHITE if count_text != "0" else Color(1, 0.4, 0.35)
			_text(font, r, count_text, HORIZONTAL_ALIGNMENT_RIGHT, r.size.y - 6, 15, col)

		# Lock for equipment not bought yet.
		if not owned:
			_draw_lock(r.position + Vector2(r.size.x - 16, 16))

	# Tooltip above the hovered slot.
	if _hover >= 0:
		var slot := slot_at(_hover)
		var r := slot_rect(_hover)
		var tip := "Empty - hover a weapon or system in the inventory (I) and press %d" % (_hover + 1)
		if not slot.is_empty():
			tip = Items.display_name(slot["id"])
			if slot["type"] == "weapon":
				tip = Items.WEAPONS[slot["id"]]["name"]
			if not _owned(slot):
				tip += "  (buy at a station)"
		var w := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs("hud", 15)).x + 20
		var box := Rect2(r.get_center().x - w / 2.0, -34, w, 26)
		draw_rect(box, Color(NeonTheme.BG, 0.95))
		draw_rect(box, Color(NeonTheme.CYAN, 0.7), false, 1.0)
		draw_string(font, Vector2(box.position.x, box.position.y + 18), tip, HORIZONTAL_ALIGNMENT_CENTER, w, Settings.fs("hud", 15), Color.WHITE)


func _owned(slot: Dictionary) -> bool:
	var id: String = slot["id"]
	if slot["type"] == "weapon":
		return data.has_equipment(id)
	var sys: Dictionary = Items.SYSTEMS[id]
	return not sys.has("equipment") or data.has_equipment(sys["equipment"])


func _has_supply(slot: Dictionary) -> bool:
	match slot["id"]:
		"missile_launcher":
			return data.count("missile") > 0
		"repair_kit":
			return data.count("repair_kit") > 0
	return true


func _text(font: Font, r: Rect2, text: String, align: HorizontalAlignment, y: float, size: int, col: Color) -> void:
	var pos := Vector2(r.position.x + 6, r.position.y + y)
	draw_string_outline(font, pos, text, align, r.size.x - 12, _hud_size(size), 4, Color(0, 0, 0, 0.9))
	draw_string(font, pos, text, align, r.size.x - 12, _hud_size(size), col)


func _draw_lock(c: Vector2) -> void:
	draw_arc(c + Vector2(0, -3), 5.0, PI, TAU, 12, NeonTheme.TEXT, 2.0, true)
	draw_rect(Rect2(c + Vector2(-7, -3), Vector2(14, 10)), NeonTheme.TEXT)
	draw_circle(c + Vector2(0, 2), 1.8, Color(0.2, 0.2, 0.25))


## HUD text size, capped at 160% so numbers stay inside the 76 px slots.
func _hud_size(base: int) -> int:
	return mini(Settings.fs("hud", base), roundi(base * 1.6))
