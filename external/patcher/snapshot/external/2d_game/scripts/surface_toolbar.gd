class_name SurfaceToolbar
extends Control
## The toolbar on foot (bottom of the screen on a planet), like the ship's:
## Inventory.TOOLBAR_SLOTS (9) slots you fill yourself (Inventory.toolbar,
## player "toolbar_foot") - hover something usable in the Field Computer's
## inventory and press 1-9 to put it there; right-click a slot to empty it.
## What can go on it:
##   rifle        your laser rifle: fire at the nearest enemy (as F); lit while you fire
##   medicine     heals HEAL health (one Medicine from what you carry)
##   energy_cell  overcharges the rifle: twice the rate of fire for OVERCHARGE s
##   food, an energy drink  gives back stamina (Stamina)
##   a skill ("skill:<id>": Skills) - a martial style (lit while you fight in it),
##                a technique, the leap, a spell; unlearned ones are dimmed
## Over the bar: the automaton's level and its experience toward the next (Skills).
## Counts are what you carry; a dark curtain shows a cooldown. Click a slot
## or press its number (PlanetSurface.use_tool).

const SLOT := 64.0
const GAP := 8.0
const NAMES := {"rifle": "Laser rifle", "medicine": "Medicine", "energy_cell": "Energy cell"}
## The icons (Items.draw_icon keys).
const ICONS := {"rifle": "laser", "medicine": "medicine", "energy_cell": "energy_cell"}
const HEAL := 50.0
const OVERCHARGE := 10.0          # s
const COOLDOWN := {"rifle": 0.0, "medicine": 2.0, "energy_cell": 20.0}

var surface: Node
var _hover := -1
var _press := -1


func _ready() -> void:
	var n := Inventory.TOOLBAR_SLOTS
	custom_minimum_size = Vector2(n * SLOT + (n - 1) * GAP, SLOT)
	size = custom_minimum_size
	mouse_exited.connect(func(): _hover = -1)
	tooltip_text = " "


func _process(_delta: float) -> void:
	if UI.redraw_due(self, 30.0):   # (cooldown curtains, counts: 30 a second is plenty)
		queue_redraw()


func slot_rect(i: int) -> Rect2:
	return Rect2(i * (SLOT + GAP), 0, SLOT, SLOT)


func _slot_at(pos: Vector2) -> int:
	for i in Inventory.TOOLBAR_SLOTS:
		if slot_rect(i).has_point(pos):
			return i
	return -1


func _bar() -> Array:
	return surface.foot_toolbar() if surface else []


func _get_tooltip(at: Vector2) -> String:
	var i := _slot_at(at)
	if i < 0 or surface == null:
		return ""
	var id: String = _bar()[i]
	match id:
		"rifle":
			return "Laser rifle  (%d)\nFire at the nearest enemy - the same as F.\nRight-click: empty this slot." % (i + 1)
		"medicine":
			return "Medicine  (%d)\nHeals %d health. Uses one Medicine from what you carry.\nRight-click: empty this slot." % [i + 1, int(HEAL)]
		"energy_cell":
			return "Energy cell  (%d)\nOvercharges your rifle: twice the rate of fire for %d s.\nUses one Energy Cell from what you carry.\nRight-click: empty this slot." % [i + 1, int(OVERCHARGE)]
	if Skills.is_skill(id):
		var sid := Skills.id_of(id)
		var rk := Skills.rank(surface.state["player"], sid)
		return "%s  (%d)  -  %s\n%s\nRight-click: empty this slot." % [Skills.SKILLS[sid]["name"], i + 1,
			("rank %d" % rk) if rk > 0 else "not learned (the Field Computer's SKILLS tab)", Skills.describe(sid, rk)]
	if Stamina.restores(id) > 0.0:
		return "%s  (%d)\nGives back %d stamina (the green ring). Uses one from what you carry.\nRight-click: empty this slot." % [Items.display_name(id), i + 1, int(Stamina.restores(id))]
	return "Empty slot  (%d)\nPut something here: open the Field Computer's inventory (I),\nhover your rifle, medicine, an energy cell, food or an energy drink and press %d -\nor a skill in its SKILLS tab (K)." % [i + 1, i + 1]


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover = _slot_at(event.position)
	elif event is InputEventMouseButton:
		var i := _slot_at(event.position)
		if i >= 0 and surface:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if event.pressed:
					_press = i
				elif i == _press and not get_viewport().gui_is_dragging():
					surface.use_tool(i)
			elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				_bar()[i] = ""   # (emptied)
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_press = -1
		accept_event()


## Drag a slot onto another (they swap), or your rifle, medicine or an energy
## cell onto a slot from the Field Computer's inventory (Inventory.toolbar_drop).
func _get_drag_data(at: Vector2) -> Variant:
	var i := _slot_at(at)
	_press = -1
	if i < 0 or surface == null or str(_bar()[i]) == "":
		return null
	var ghost := ItemSlot.make(ICONS.get(_bar()[i], _bar()[i]), 0, SLOT * 0.8)
	ghost.modulate = Color(1, 1, 1, 0.8)
	var holder := Control.new()
	holder.add_child(ghost)
	ghost.position = -ghost.custom_minimum_size * 0.5
	set_drag_preview(holder)
	return {"src": "toolbar", "which": "foot", "index": i, "id": _bar()[i]}


func _can_drop_data(at: Vector2, d: Variant) -> bool:
	return surface != null and d is Dictionary and _slot_at(at) >= 0 and Inventory.toolbar_accepts(d, true)


func _drop_data(at: Vector2, d: Variant) -> void:
	Inventory.toolbar_drop(_bar(), _slot_at(at), d, true)
	queue_redraw()


func _draw() -> void:
	if surface == null or surface.pilot == null:
		return
	var font := ThemeDB.fallback_font
	var inv: Dictionary = surface.carried()
	var bar := _bar()
	# The automaton's level, and its experience toward the next (Skills).
	var st: Dictionary = Skills.state(surface.state["player"])
	var lv := int(st["level"])
	var need := Skills.xp_need(lv)
	var xr := Rect2(0, -9, size.x, 4)
	draw_rect(xr, Color(0, 0, 0, 0.55))
	if lv < Skills.MAX_LEVEL:
		draw_rect(Rect2(xr.position, Vector2(xr.size.x * clampf(float(st["xp"]) / maxf(1.0, need), 0.0, 1.0), xr.size.y)), Color(1.0, 0.82, 0.4, 0.9))
	var tag := "LV %d%s" % [lv, ("  ·  %d point%s to spend (K)" % [int(st["points"]), "" if int(st["points"]) == 1 else "s"]) if int(st["points"]) > 0 else ""]
	draw_string(font, Vector2(0, -14), tag, HORIZONTAL_ALIGNMENT_LEFT, -1, Settings.fs("hud", 13), Color(1.0, 0.82, 0.4))
	for i in Inventory.TOOLBAR_SLOTS:
		var id: String = bar[i]
		var r := slot_rect(i)
		var count := int(inv.get(id, 0)) if id in ["medicine", "energy_cell"] or Stamina.restores(id) > 0.0 else -1
		var active: bool = (id == "rifle" and surface.pilot.trigger != null) or (id == "energy_cell" and surface.overcharge_left() > 0.0)
		var sid := Skills.id_of(id)
		var rank := Skills.rank(surface.state["player"], sid) if sid != "" else 0
		if sid != "":
			active = (surface.pilot.style == sid and surface.pilot.fighting()) or (sid == "guard" and surface.pilot.guard_left > 0.0) \
				or (sid == "aegis" and surface.pilot.dome_left > 0.0)
		draw_rect(r, Color(NeonTheme.BG, 0.88 if id != "" else 0.55))
		var border := Color(NeonTheme.CYAN.darkened(0.3), 0.7 if id != "" else 0.35)
		if active:
			border = NeonTheme.CYAN
		elif i == _hover:
			border = Color(NeonTheme.CYAN.lightened(0.3), 0.9)
		draw_rect(r, border, false, 3.0 if active else 1.5)
		if active:
			draw_rect(r.grow(-3), Color(NeonTheme.CYAN, 0.1))
		if id != "":
			Items.draw_icon(self, ICONS.get(id, id), r.grow(-14) if sid == "" else r.grow(-7), count == 0 or (sid != "" and rank <= 0))
			if sid != "" and surface.pilot.style == sid:     # (the style you fight in: a mark under it)
				draw_rect(Rect2(r.position.x + 8, r.end.y - 5, r.size.x - 16, 3), Skills.school_color(sid))
			# Cooldown: a dark curtain shrinking upward.
			var left: float = surface.tool_cooldown(i)
			var cd: float = COOLDOWN.get(id, Stamina.COOLDOWN if Stamina.restores(id) > 0.0 else 0.0)
			if sid != "":
				cd = Skills.cooldown(sid, maxi(1, rank))
			if left > 0.0 and cd > 0.0:
				var f := clampf(left / cd, 0.0, 1.0)
				draw_rect(Rect2(r.position.x, r.end.y - r.size.y * f, r.size.x, r.size.y * f), Color(0, 0, 0, 0.55))
				draw_string(font, r.position + Vector2(0, r.size.y * 0.58), "%d" % ceili(left), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 18, Color.WHITE)
		draw_string(font, r.position + Vector2(5, 15), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UI.TEXT_DIM)
		if count >= 0:
			draw_string(font, r.position + Vector2(0, r.size.y - 5), str(count), HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 5, 14,
				Color.WHITE if count > 0 else Color(0.6, 0.4, 0.4))
