class_name EquipDoll
extends Control
## An equipment screen in the manner of action RPGs: the ship (or the
## automaton - you on a planet) drawn large in the middle, and round it its
## areas' slots - each group placed beside its area and joined to it by a
## line. Ships: nose, wings, hull, thrusters, cargo bay (Shipyard.AREAS);
## the automaton: head, back, torso, arms, hand, legs (Gear.AREA_OF_SLOT).
## The slots are ItemSlots made by the page that shows the doll (it knows
## what dragging onto them and right-clicking them does):
##   var d := EquipDoll.new()
##   d.picture = tex
##   d.add_group("nose", "NOSE", Vector2(0.5, 0.0), Vector2(0.5, 0.1), false, [slot, slot])
## `at`: where the group sits in the doll (0..1 each way: its edge-most
## point); `anchor`: the spot it belongs to on the picture (0..1 of it);
## vertical: the slots stacked (else side by side).

const MAX_RUN := 4
const GAP := 12.0     # between the slots and the picture's frame - the same for every group
const FRAME := 14.0   # the frame drawn round the picture
const SPREAD := 8.0   # between groups on the same side
var picture: Texture2D
## The character's 3D model instead of the picture (ModelView: turned by dragging) - laid where the picture goes.
var view: Control:
	set(v):
		view = v
		if v and v.get_parent() == null:
			add_child(v)
			move_child(v, 0)
		_layout()
var picture_scale := 0.62            # of the doll's height
var groups: Array = []               # [{key, name, at, anchor, vertical, box: Container}]
var _pic_rect := Rect2()


func _init() -> void:
	custom_minimum_size = Vector2(470, 360)
	mouse_filter = Control.MOUSE_FILTER_PASS


func add_group(key: String, title: String, at: Vector2, anchor: Vector2, vertical: bool, slots: Array) -> void:
	# Up to MAX_RUN slots in a line; more (an over-full area) wrap into more lines.
	var box := GridContainer.new()
	box.columns = (ceili(slots.size() / float(MAX_RUN)) if vertical else mini(slots.size(), MAX_RUN)) if not slots.is_empty() else 1
	box.add_theme_constant_override("h_separation", 3)
	box.add_theme_constant_override("v_separation", 3)
	var cap := UI.label(title, 12, NeonTheme.HEAD)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var holder := VBoxContainer.new()
	holder.add_theme_constant_override("separation", 1)
	holder.add_child(cap)
	box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER   # (its slots centred under the caption: a side's line up)
	holder.add_child(box)
	for s in slots:
		box.add_child(s)
	add_child(holder)
	groups.append({"key": key, "name": title, "at": at, "anchor": anchor, "vertical": vertical, "box": holder})
	_layout.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()


func _layout() -> void:
	# The picture in the middle, as big as fits once the slot groups have
	# room round it; every group then sits the same distance (GAP) from the
	# picture's frame: left groups just left of it, right ones just right, the
	# top one just above, the bottom one just below - each along that side at
	# its own spot (`at`).
	var left := 0.0
	var right := 0.0
	var top := 0.0
	var bottom := 0.0
	for g in groups:
		var ms: Vector2 = (g["box"] as Control).get_combined_minimum_size()
		match _side(g):
			"left": left = maxf(left, ms.x)
			"right": right = maxf(right, ms.x)
			"top": top = maxf(top, ms.y)
			"bottom": bottom = maxf(bottom, ms.y)
	var room := FRAME + GAP
	var aspect := 1.0
	if picture:
		aspect = picture.get_width() / maxf(1.0, picture.get_height())
	var h := minf(size.y * picture_scale, size.y - top - bottom - room * 2.0)
	var w := h * aspect
	var max_w := size.x - maxf(left, right) * 2.0 - room * 2.0   # (centred: room for the wider side on both)
	if w > max_w:
		w = max_w
		h = w / aspect
	w = maxf(w, 10.0)
	h = maxf(h, 10.0)
	var cy := top + room + (size.y - top - bottom - room * 2.0) / 2.0
	_pic_rect = Rect2(Vector2(size.x / 2.0 - w / 2.0, cy - h / 2.0), Vector2(w, h))
	var frame := _pic_rect.grow(FRAME)
	# Along each side: each group at its own spot, then spread so none overlap
	# (in order; pulled back inside the doll if they run past its edge).
	var sides := {"left": [], "right": [], "top": [], "bottom": []}
	for g in groups:
		sides[_side(g)].append(g)
	for side in sides:
		var along_y: bool = side in ["left", "right"]
		var lo: float = frame.position.y if along_y else frame.position.x
		var hi: float = frame.end.y if along_y else frame.end.x
		var items := []
		var thick := 0.0   # the side's widest (left / right) or tallest (top / bottom) group: all made that size
		for g in sides[side]:
			var ms: Vector2 = (g["box"] as Control).get_combined_minimum_size()
			thick = maxf(thick, ms.x if along_y else ms.y)
			items.append([0.0, ms.y if along_y else ms.x, g, ms, Vector2(g["at"]).y if along_y else Vector2(g["at"]).x])
		items.sort_custom(func(a, b): return a[4] < b[4])
		# Evenly spread along the frame's side (equal space between them and
		# at the ends); with too little room, stacked SPREAD apart.
		var total := 0.0
		for it in items:
			total += it[1]
		var free_len: float = (hi - lo) - total
		var step: float = free_len / (items.size() + 1) if free_len > SPREAD * (items.size() + 1) else SPREAD
		var cur: float = lo + step if free_len > SPREAD * (items.size() + 1) else lo + (hi - lo - total - SPREAD * (items.size() - 1)) / 2.0
		for it in items:
			it[0] = cur
			cur += it[1] + step
			# (every group on the side as wide - or as tall - as the biggest: their slots share a centre line)
			it[3] = Vector2(thick, it[3].y) if along_y else Vector2(it[3].x, thick)
		var limit: float = size.y if along_y else size.x
		if not items.is_empty() and items[0][0] < 0.0:
			var under: float = -items[0][0]
			for it in items:
				it[0] += under
		if not items.is_empty() and items[-1][0] + items[-1][1] > limit:
			var over: float = items[-1][0] + items[-1][1] - limit
			for it in items:
				it[0] = maxf(0.0, it[0] - over)
		for it in items:
			var ms: Vector2 = it[3]
			var pos := Vector2.ZERO
			match side:
				"left": pos = Vector2(frame.position.x - GAP - ms.x, it[0])
				"right": pos = Vector2(frame.end.x + GAP, it[0])
				"top": pos = Vector2(it[0], frame.position.y - GAP - ms.y)
				_: pos = Vector2(it[0], frame.end.y + GAP)
			var box: Control = it[2]["box"]
			box.position = pos.clamp(Vector2.ZERO, (size - ms).max(Vector2.ZERO))
			box.size = ms
	if view:
		# (the model's frame wider than the picture's: room to turn round, its rifle out to the side)
		var r := _pic_rect.grow_individual(_pic_rect.size.x * 0.35, 0.0, _pic_rect.size.x * 0.35, 0.0)
		view.position = r.position
		view.size = r.size
	queue_redraw()


## Which side of the picture a group sits on (from its `at`).
func _side(g: Dictionary) -> String:
	var at := Vector2(g["at"])
	if at.x <= 0.05:
		return "left"
	if at.x >= 0.95:
		return "right"
	return "top" if at.y < 0.5 else "bottom"


## The point a group's line leaves from (the side of its box facing the picture).
func _box_point(g: Dictionary) -> Vector2:
	var box: Control = g["box"]
	var r := Rect2(box.position, box.size)
	var c := _pic_rect.get_center()
	var p := r.get_center()
	if absf(p.x - c.x) > absf(p.y - c.y) * 1.2:
		return Vector2(r.end.x if p.x < c.x else r.position.x, p.y)
	return Vector2(p.x, r.end.y if p.y < c.y else r.position.y)


func _draw() -> void:
	# A faint frame of the console behind the picture.
	draw_rect(_pic_rect.grow(FRAME), Color(NeonTheme.BG_LIGHT, 0.5))
	draw_rect(_pic_rect.grow(FRAME), Color(NeonTheme.CYAN, 0.25), false, 1.0)
	if picture and view == null:
		draw_texture_rect(picture, _pic_rect, false)
	for g in groups:
		var a: Vector2 = _pic_rect.position + _pic_rect.size * Vector2(g["anchor"])
		var b := _box_point(g)
		var col := Color(NeonTheme.CYAN, 0.55)
		draw_line(b, a, col, 1.5, true)
		draw_circle(a, 4.0, col)
		draw_arc(a, 7.0, 0, TAU, 16, Color(NeonTheme.CYAN, 0.3), 1.0, true)
