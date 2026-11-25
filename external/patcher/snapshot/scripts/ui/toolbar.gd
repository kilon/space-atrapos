extends Control
## Bottom toolbar: Inventory.TOOLBAR_SLOTS (9) slots you fill yourself - the
## ship's (PlayerData.toolbar) in it, the automaton's (toolbar_foot) on foot:
## drag anything usable onto a slot (from the Automaton's inventory, the
## automaton's loadout and tools, the ship's fittings), drag a slot to another
## to swap them, off the bar (or right-click it) to empty it. Shows each slot's
## icon and count, what's on (a weapon kind firing, gear equipped), cooldowns and
## locked (not yet bought) systems. Click a slot or press its number key: what's
## on it done (ToolbarUse, in the 3D game: the ship's `cosmos`).

signal slot_pressed(index: int)

const SLOT := 70.0
const GAP := 8.0

var ship: Node2D
var data: Node
var foot := false                   # (on foot - Cosmos.walker: the automaton's bar)
var _hover := -1
var _press := -1                    # the slot pressed (a click is its release, not a drag)
var _dragged := -1                  # the slot being dragged off (emptied if it's dropped nowhere)


func _ready() -> void:
	var count := Inventory.TOOLBAR_SLOTS
	custom_minimum_size = Vector2(count * SLOT + (count - 1) * GAP, SLOT)
	mouse_exited.connect(func(): _hover = -1)


var _shown := ""


func _process(_delta: float) -> void:
	# (looked at 30 times a second, drawn again only when what it shows has
	# changed - a cooldown's second, a count, a weapon switched: a redraw is ~0.3 ms)
	if UI.redraw_due(self, 30.0):
		var cos := _cosmos()
		foot = cos != null and cos.get("walker") != null
		var sig := _signature()
		if sig != _shown:
			_shown = sig
			queue_redraw()


## The bar shown: the automaton's on foot, else the ship's.
func bar() -> Array:
	if data == null:
		return []
	return data.toolbar_foot if foot else data.toolbar


## What the toolbar shows, as text (redrawn when it changes).
func _signature() -> String:
	if ship == null or data == null:
		return ""
	var parts := PackedStringArray([str(_hover), str(foot)])
	for i in Inventory.TOOLBAR_SLOTS:
		var slot := slot_at(i)
		if slot.is_empty():
			parts.append("-")
			continue
		var id: String = slot["id"]
		var owned := _owned(slot)
		var bits := "%s%d%d%d:%d" % [id, int(owned), int(owned and _has_supply(slot)), int(_lit(slot)), Inventory.toolbar_count(data, id, foot)]
		if slot["type"] == "system":
			bits += ":%d:%d" % [ceili(_cooldown(id) * 30.0), int(id == "afterburner" and ship.boost_time > 0.0)]
		parts.append(bits)
	return "|".join(parts)


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
				press(i)
			if not event.pressed:
				_press = -1
		elif event.pressed and i >= 0 and event.button_index == MOUSE_BUTTON_RIGHT and data:
			Inventory.toolbar_clear(bar(), i)
		accept_event()


## 1-9 (Keybinds' slot_1..9): that slot pressed - unless a menu took the key.
func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or data == null or not (event is InputEventKey or event is InputEventJoypadButton):
		return
	if not event.is_pressed() or event.is_echo():
		return
	var i: int = Keybinds.slot_pressed(event)
	if i >= 0:
		press(i)
		get_viewport().set_input_as_handled()


## Slot `i` used: in the 3D game what's on it done (ToolbarUse) and its
## message flashed; else slot_pressed for whoever listens.
func press(i: int) -> void:
	var slot := slot_at(i)
	if slot.is_empty():
		return
	var cos := _cosmos()
	if cos == null:
		slot_pressed.emit(i)
		return
	var said := ToolbarUse.use(cos, data, str(slot["id"]), foot)
	var hud: Variant = cos.get("hud")
	if said != "" and hud is Node and hud.has_method("flash"):
		hud.flash(said)
	_shown = ""


## The 3D game (the ship here is its CosmosShipProxy: `cosmos`), or null.
func _cosmos() -> Node:
	var c: Variant = ship.get("cosmos") if ship else null
	return c if c is Node and is_instance_valid(c) else null


## Seconds before a system can be used again.
func _cooldown(id: String) -> float:
	return ToolbarUse.cooldown_left(id) if _cosmos() else float(ship.cooldown_left(id))


## Drag a slot onto another (they swap), off the bar (emptied), or something
## usable onto a slot from the Automaton's inventory (Inventory.toolbar_drop).
func _get_drag_data(at: Vector2) -> Variant:
	var i := _slot_at(at)
	_press = -1
	var b := bar()
	if i < 0 or data == null or str(b[i]) == "":
		return null
	var ghost := ItemSlot.make(b[i], 0, SLOT * 0.8)
	ghost.modulate = Color(1, 1, 1, 0.8)
	var holder := Control.new()
	holder.add_child(ghost)
	ghost.position = -ghost.custom_minimum_size * 0.5
	set_drag_preview(holder)
	_dragged = i
	return {"src": "toolbar", "which": "foot" if foot else "ship", "index": i, "id": b[i]}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragged >= 0:
		if not get_viewport().gui_is_drag_successful() and data:
			Inventory.toolbar_clear(bar(), _dragged)   # (dropped off the bar: emptied)
		_dragged = -1
		_shown = ""


func _can_drop_data(at: Vector2, d: Variant) -> bool:
	return data != null and d is Dictionary and _slot_at(at) >= 0 and Inventory.toolbar_accepts(d, foot)


func _drop_data(at: Vector2, d: Variant) -> void:
	Inventory.toolbar_drop(bar(), _slot_at(at), d, foot)
	_shown = ""
	queue_redraw()


## The slot's {type, id} ({} when empty): type Inventory.toolbar_kind's.
func slot_at(i: int) -> Dictionary:
	var b := bar()
	if i < 0 or i >= b.size():
		return {}
	var id := str(b[i])
	var kind := Inventory.toolbar_kind(id, foot)
	if kind == "":
		return {}
	return {"type": kind, "id": id}


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
		var owned := _owned(slot)
		var active := _lit(slot)   # (a weapon kind firing, gear equipped)

		# Background + border.
		# The GUI palette (NeonTheme).
		draw_rect(r, Color(NeonTheme.BG, 0.88))
		var border := Color(NeonTheme.CYAN.darkened(0.3), 0.7)
		if active:
			border = NeonTheme.CYAN
		elif i == _hover:
			border = Color(NeonTheme.CYAN.lightened(0.3), 0.9)
		draw_rect(r, border, false, 3.0 if active else 1.5)
		if active:   # (the active slot: lit inside, a glow round it, a bar along its foot)
			draw_rect(r.grow(-3), Color(NeonTheme.CYAN, 0.18))
			draw_rect(r.grow(3), Color(NeonTheme.CYAN, 0.45), false, 2.0)
			draw_rect(r.grow(6), Color(NeonTheme.CYAN, 0.18), false, 2.0)
			draw_rect(Rect2(r.position.x + 6, r.end.y - 5, r.size.x - 12, 3), NeonTheme.CYAN)

		# Icon (the baked texture when there is one: a draw call).
		var usable := owned and _has_supply(slot)
		var tex := Items.icon_texture(id, not usable)
		if tex:
			draw_texture_rect(tex, r.grow(-16), false)
		else:
			Items.draw_icon(self, id, r.grow(-16), not usable)

		# Cooldown overlay (systems): dark curtain shrinking upward + seconds.
		if slot["type"] == "system":
			var left: float = _cooldown(id)
			if left > 0.0:
				var frac: float = clampf(left / maxf(0.1, float(Items.SYSTEMS[id].get("cooldown", 1.0))), 0.0, 1.0)
				draw_rect(Rect2(r.position + Vector2(0, r.size.y * (1.0 - frac)), Vector2(r.size.x, r.size.y * frac)),
						Color(0, 0, 0, 0.6))
				_text(font, r, "%.0f" % ceilf(left), HORIZONTAL_ALIGNMENT_CENTER, r.size.y / 2.0 + 8, 22, Color.WHITE)
			if id == "afterburner" and ship.boost_time > 0.0:
				draw_rect(r.grow(-2), Color(1.0, 0.6, 0.2, 0.25))

		# Hotkey number.
		_text(font, r, str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, 17, 14, NeonTheme.TEXT)

		# How many you have (ammo, supplies, gear not on).
		var n := Inventory.toolbar_count(data, id, foot)
		if n >= 0 and (owned or slot["type"] != "weapon"):
			var col := Color.WHITE if n > 0 else Color(1, 0.4, 0.35)
			_text(font, r, str(n), HORIZONTAL_ALIGNMENT_RIGHT, r.size.y - 6, 15, col)

		# Lock for equipment not bought yet.
		if not owned:
			_draw_lock(r.position + Vector2(r.size.x - 16, 16))

	# The hovered slot's name above it.
	if _hover >= 0:
		var slot := slot_at(_hover)
		if slot.is_empty():
			return
		var r := slot_rect(_hover)
		var tip := Items.display_name(slot["id"])
		if slot["type"] == "weapon":
			tip = Items.WEAPONS[slot["id"]]["name"]
		var w := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs("hud", 15)).x + 20
		var box := Rect2(r.get_center().x - w / 2.0, -34, w, 26)
		draw_rect(box, Color(NeonTheme.BG, 0.95))
		draw_rect(box, Color(NeonTheme.CYAN, 0.7), false, 1.0)
		draw_string(font, Vector2(box.position.x, box.position.y + 18), tip, HORIZONTAL_ALIGNMENT_CENTER, w, Settings.fs("hud", 15), Color.WHITE)


## Lit: a weapon kind firing, automaton gear equipped, a ship module fitted.
func _lit(slot: Dictionary) -> bool:
	match slot["type"]:
		"weapon":
			return _owned(slot) and not data.weapons_off.has(slot["id"])
		"gear", "ship_gear":
			return Inventory.toolbar_equipped(data, slot["id"], foot)
		"tool":   # (the tool in the automaton's hands)
			return foot and ToolbarUse.held(_cosmos()) == slot["id"]
	return false


## Bought: a weapon kind fitted, a system installed (the rest: always).
func _owned(slot: Dictionary) -> bool:
	var id: String = slot["id"]
	match slot["type"]:
		"weapon":
			return data.has_equipment(id)
		"system":
			var sys: Dictionary = Items.SYSTEMS[id]
			return not sys.has("equipment") or data.has_equipment(sys["equipment"])
	return true


## Something to use: missiles for the launcher, one of a supply, gear to equip.
func _has_supply(slot: Dictionary) -> bool:
	if slot["id"] == "missile_launcher":
		return data.count("missile") > 0
	return Inventory.toolbar_count(data, slot["id"], foot) != 0


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
