class_name UI
## Small helpers for building the code-generated panels consistently.

static var TEXT_DIM := Color(0.78, 0.6, 0.42)
const GOLD := Color(1.0, 0.82, 0.3)


## Neon cut-corner panel (see NeonTheme); content margins left to the caller.
## Every panel has the same look - amber border, bracket corners and the corner
## hatch - whatever colour the caller asks for (the GUI keeps one colour theme).
static func panel_style(_border: Color) -> NeonBox:
	var s := NeonTheme.box(Color(NeonTheme.CYAN, 0.7), Color(NeonTheme.BG, 0.96), 1, 8, 14)
	s.accent = NeonTheme.CYAN
	s.content_margin_left = 2
	s.content_margin_right = 2
	s.content_margin_top = 2
	s.content_margin_bottom = 2
	return s


static func label(text: String, size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if size >= 24:   # titles: the heavy neon heading font
		l.add_theme_font_override("font", NeonTheme.heavy_font())
	return l


## A label that wraps to its column (`width`: the narrowest it gets) - for
## help lines and stats that would otherwise widen a page at bigger text.
static func note(text: String, size := 12, width := 300.0, color := TEXT_DIM) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	return l


## A section heading: heavy letter-spaced capitals over a faint rule, with a
## lit tick at its left end.
static func section(text: String, color := NeonTheme.HEAD) -> Label:
	var l := label(text, 16, color)
	l.add_theme_constant_override("outline_size", 0)
	l.add_theme_font_override("font", NeonTheme.heavy_font())
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(color, 0.3)
	sb.border_width_bottom = 1
	sb.content_margin_left = 10
	sb.content_margin_bottom = 2
	l.add_theme_stylebox_override("normal", sb)
	l.draw.connect(func():
		l.draw_rect(Rect2(0, 3, 3, l.size.y - 7), color))
	return l


static func button(text: String, on_pressed: Callable, size := 16) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.pressed.connect(on_pressed)
	return b


## A light button style for pages full of small buttons (the outfitter's,
## the shipyard's, the sell list's cards): plain flat boxes in the palette -
## a couple of draw calls each, where the panel style (glow, brackets, rail)
## takes ten; shared, so they batch. Lit amber under the mouse, as usual.
static var _light: Dictionary = {}

static func light_button(b: Button) -> Button:
	if _light.is_empty() or _light.get("look", null) != NeonTheme.CYAN:
		var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
			var sb := StyleBoxFlat.new()
			sb.bg_color = bg
			sb.border_color = border
			sb.set_border_width_all(1)
			sb.content_margin_left = 6
			sb.content_margin_right = 6
			sb.content_margin_top = 2
			sb.content_margin_bottom = 2
			return sb
		_light = {"look": NeonTheme.CYAN,
			"normal": mk.call(Color(NeonTheme.BG_LIGHT, 0.9), Color(NeonTheme.CYAN, 0.55)),
			"hover": mk.call(Color(NeonTheme.CYAN, 0.95), NeonTheme.PINK),
			"pressed": mk.call(Color(NeonTheme.PINK, 0.95), NeonTheme.PINK),
			"disabled": mk.call(Color(NeonTheme.BG, 0.6), Color(NeonTheme.DISABLED, 0.3)),
			"focus": mk.call(Color(0, 0, 0, 0), Color(NeonTheme.PINK, 0.9))}
	for k in ["normal", "hover", "pressed", "disabled", "focus"]:
		b.add_theme_stylebox_override(k, _light[k])
	b.add_theme_stylebox_override("hover_pressed", _light["pressed"])
	b.add_theme_color_override("font_hover_color", NeonTheme.INK)
	b.add_theme_color_override("font_pressed_color", NeonTheme.INK)
	b.add_theme_color_override("icon_hover_color", NeonTheme.INK)
	return b


## A light panel for cards by the dozen (the shipyard's): a flat box in the
## palette, shared (it batches).
static var _light_panel: StyleBoxFlat

static func light_panel(p: PanelContainer) -> PanelContainer:
	if _light_panel == null:
		_light_panel = StyleBoxFlat.new()
		_light_panel.bg_color = Color(NeonTheme.BG_LIGHT, 0.85)
		_light_panel.border_color = Color(NeonTheme.CYAN, 0.35)
		_light_panel.set_border_width_all(1)
		_light_panel.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", _light_panel)
	return p


static func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


## Full-screen dim + centred styled panel; returns the VBox to fill.
## A dimmed full-screen backdrop with a panel; returns its content box.
## full: the panel fills the window (with a small margin) instead of being
## centred at min_size.
static func modal(parent: Control, border: Color, min_size: Vector2, full := false) -> VBoxContainer:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.0, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(dim)

	var holder: Container
	if full:
		var m := MarginContainer.new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			m.add_theme_constant_override("margin_" + side, 18)
		holder = m
	else:
		holder = CenterContainer.new()
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(holder)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.add_theme_stylebox_override("panel", panel_style(border))
	holder.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	return vbox


## Row of toggle buttons acting as tabs; calls on_select(index) when clicked.
## expand: the tabs share the whole width.
## Selected: the reference's lit orange tab; the others dark glass with a
## cyan edge (accent is kept for callers but the theme decides the colours).
## A sum of money with thousands separators ("1,250,000").
static func money(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func tab_bar(names: Array, on_select: Callable, _accent := Color(0.4, 0.85, 1.0), expand := true) -> HBoxContainer:
	var accent := NeonTheme.PINK
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in names.size():
		var b := Button.new()
		b.text = names[i]
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(170, 42)
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_font_override("font", NeonTheme.heavy_font())
		b.add_theme_font_size_override("font_size", 20)
		b.add_theme_color_override("font_color", NeonTheme.TEXT_DIM)
		b.add_theme_color_override("font_hover_color", NeonTheme.HEAD)
		b.add_theme_stylebox_override("normal", _tab_style(NeonTheme.BG, Color(NeonTheme.CYAN, 0.4)))
		b.add_theme_stylebox_override("hover", _tab_style(NeonTheme.hi_bg(1.0, 0.22), Color(NeonTheme.CYAN, 0.8)))
		b.add_theme_stylebox_override("pressed", _tab_style(NeonTheme.CYAN, NeonTheme.CYAN, 3, true))
		b.add_theme_stylebox_override("hover_pressed", _tab_style(NeonTheme.CYAN.lightened(0.08), NeonTheme.CYAN, 3, true))
		b.add_theme_color_override("font_pressed_color", NeonTheme.INK)
		b.add_theme_color_override("font_hover_pressed_color", NeonTheme.INK)
		b.add_theme_color_override("icon_pressed_color", NeonTheme.INK)
		b.add_theme_color_override("icon_hover_pressed_color", NeonTheme.INK)
		b.add_theme_color_override("icon_hover_color", NeonTheme.HEAD)
		b.pressed.connect(on_select.bind(i))
		if expand:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			# (each its share by its name's length - its icon and edges count as
			# 4 letters - so a long name isn't cut while a short one has room)
			b.size_flags_stretch_ratio = str(names[i]).length() + 4.0
			b.custom_minimum_size.x = 60
			b.clip_text = true
		bar.add_child(b)
	return bar


static func select_tab(bar: HBoxContainer, index: int) -> void:
	for i in bar.get_child_count():
		(bar.get_child(i) as Button).set_pressed_no_signal(i == index)


## A tab: slanted, dark with an amber edge; the selected one lit solid amber
## (`solid`) with a thick pale-gold foot.
static func _tab_style(bg: Color, border: Color, bottom := 1, solid := false) -> NeonBox:
	var s := NeonTheme.box(border, Color(bg, 0.94), 1, 8 if solid else 0, 9)
	s.fill_solid = solid
	if solid:
		s.border_color = NeonTheme.CYAN
		s.border_width_bottom = bottom
	s.skew = Vector2(0.18, 0)
	s.content_margin_left = 14
	s.content_margin_right = 14
	return s


## Rescales every text control under `root` (inclusive) to the user's text
## size for `category` (see Settings.TEXT_CATEGORIES). Each control's original
## size is remembered the first time, so calling this again never compounds.
static func scale_fonts(root: Node, category: String, max_scale := 100.0) -> void:
	# (marked: text added to it later gets the same size - Settings, fit_text)
	root.set_meta("text_scale", [category, max_scale])
	var s := minf(Settings.font_scale(category), max_scale)
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n.has_meta("fixed_font"):
			continue   # (e.g. Talos's rail: the same size everywhere)
		stack.append_array(n.get_children())
		if n is Control:
			_scale_text(n, s)


## One control's text at scale `s` of the size it was made with (kept in a
## meta, so scaling again doesn't compound), never under Settings.MIN_FONT.
static func _scale_text(n: Control, s: float) -> void:
	if n.get_meta("scaled_to", -1.0) == s:
		return   # (already at this size: setting it again relays the control out for nothing)
	n.set_meta("scaled_to", s)
	for key in _text_keys(n):
		var meta: String = "base_" + key
		if not n.has_meta(meta):
			n.set_meta(meta, n.get_theme_font_size(key))
		n.add_theme_font_size_override(key, maxi(Settings.MIN_FONT, roundi(n.get_meta(meta) * s)))


static func _text_keys(n: Control) -> Array:
	if n is RichTextLabel:
		return ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size", "mono_font_size"]
	if n is Label or n is Button or n is LineEdit or n is TextEdit or n is Tree or n is ItemList:
		return ["font_size"]
	return []


## A text control added to the tree: its screen's text size if the screen
## was scaled (the nearest ancestor marked by scale_fonts; none under a
## fixed_font one), and never under Settings.MIN_FONT.
static func fit_text(n: Control) -> void:
	var p: Node = n
	while p != null:
		if p.has_meta("fixed_font"):
			break
		if p.has_meta("text_scale"):
			var mark: Array = p.get_meta("text_scale")
			_scale_text(n, minf(Settings.font_scale(str(mark[0])), float(mark[1])))
			return
		p = p.get_parent()
	for key in _text_keys(n):
		if n.get_theme_font_size(key) < Settings.MIN_FONT:
			n.add_theme_font_size_override(key, Settings.MIN_FONT)


## Font size that fits `text` into `width` pixels (shrinks if needed).
static func fit_size(font: Font, text: String, size: int, width: float) -> int:
	while size > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
		size -= 1
	return size


## Yes / No confirmation box over everything; pauses the game while open.
static func confirm(owner: Node, title: String, text: String, on_yes: Callable, yes_text := "Yes", no_text := "No") -> void:
	var tree := owner.get_tree()
	var was_paused := tree.paused
	tree.paused = true
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var box := modal(root, Color(0.4, 0.85, 1.0), Vector2(520, 0))
	box.add_child(label(title, 24, NeonTheme.HEAD))
	var t := label(text, 17, NeonTheme.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(t)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	var close := func():
		tree.paused = was_paused
		layer.queue_free()
	var no := button(no_text, close, 18)
	no.custom_minimum_size = Vector2(130, 44)
	var yes := button(yes_text, func():
		close.call()
		on_yes.call(), 18)
	yes.custom_minimum_size = Vector2(130, 44)
	row.add_child(no)
	row.add_child(yes)
	box.add_child(row)
	scale_fonts(root, "menu", 1.6)
	yes.grab_focus()


## A dialog with several choices: options [[label, Callable], ...] left to
## right (the last is the default button). Each closes the dialog, then runs
## its Callable (an empty Callable just closes it - e.g. Cancel). Esc cancels.
## `vertical`: the options one under another, full width (a conversation's
## questions), instead of a row of buttons at the right.
static func choice(owner: Node, title: String, text: String, options: Array, vertical := false) -> void:
	var tree := owner.get_tree()
	var was_paused := tree.paused
	tree.paused = true
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	owner.add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	var box := modal(root, Color(0.4, 0.85, 1.0), Vector2(620, 0))
	box.add_child(label(title, 24, NeonTheme.HEAD))
	var t := label(text, 17, NeonTheme.TEXT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(t)
	var row: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	if not vertical:
		row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8 if vertical else 12)
	var close := func():
		tree.paused = was_paused
		layer.queue_free()
	var last: Button = null
	for o in options:
		var cb: Callable = o[1]
		var b := button(o[0], func():
			close.call()
			if cb.is_valid():
				cb.call(), 18)
		b.custom_minimum_size = Vector2(150, 44)
		if vertical:
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if last == null:
				b.ready.connect(b.grab_focus)   # (the first question ready for Enter)
		row.add_child(b)
		last = b
	box.add_child(row)
	# Esc = cancel (the option with an empty Callable, if any).
	var esc := Node.new()
	esc.process_mode = Node.PROCESS_MODE_ALWAYS
	esc.set_script(_EscCatcher)
	esc.set("on_esc", close)
	root.add_child(esc)
	scale_fonts(root, "menu", 1.6)
	if last and not vertical:
		last.grab_focus()


## (Esc closes a choice dialog.)
const _EscCatcher := preload("res://scripts/esc_catcher.gd")


## Asks what to do with unsaved changes before leaving: Save (then leave),
## Exit without saving (discard(), then leave), or Cancel (stay).
static func unsaved(owner: Node, what: String, save: Callable, discard: Callable, leave: Callable) -> void:
	choice(owner, "Unsaved changes", "%s has unsaved changes. Save them before leaving?" % what, [
		["Cancel", Callable()],
		["Exit without saving", func():
			if discard.is_valid():
				discard.call()
			leave.call()],
		["Save and exit", func():
			save.call()
			leave.call()],
	])


## Right-click style popup menu at a screen position.
## items: [[label, Callable], ...]
static func context_menu(owner: Node, at: Vector2, items: Array, title := "COMMANDS") -> void:
	var m := PopupMenu.new()
	m.theme = NeonTheme.build()
	m.add_theme_font_size_override("font_size", Settings.fs("menu", 16))
	m.add_theme_font_override("font_separator", NeonTheme.heavy_font())
	m.add_theme_font_size_override("font_separator_size", Settings.fs("menu", 13))
	m.add_theme_color_override("font_separator_color", NeonTheme.PINK.lightened(0.25))
	if title != "":
		m.add_separator(title)
	for i in items.size():
		m.add_item(items[i][0], i)
	m.id_pressed.connect(func(id): (items[id][1] as Callable).call())
	m.popup_hide.connect(m.queue_free)
	owner.add_child(m)
	m.popup(Rect2i(Vector2i(at), Vector2i.ZERO))


## The in-game Esc menu (pause menu), if this scene has one.
static func esc_menu() -> Control:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.get_first_node_in_group("esc_menu") as Control


static func esc_menu_open() -> bool:
	var m := esc_menu()
	return m != null and m.visible


## Opens the Esc menu (the dialogue box uses it; menus close on Esc - Esc again opens this).
static func open_esc_menu() -> void:
	var m := esc_menu()
	if m and not m.visible:
		m.open()


static var _reset_icon: Texture2D

## Circular-arrow "reset" icon (24 px).
static func reset_icon() -> Texture2D:
	if _reset_icon == null:
		var col := Color(1.0, 0.86, 0.68)
		_reset_icon = Icons.paint(24, 24, [
			{"pts": Icons.arc(Vector2(12, 13), 7.0, -1.25, 4.1), "closed": false, "stroke": col, "width": 2.4},
			{"pts": Icons.poly([[6.4, 3.6], [12.4, 5.6], [7.6, 10.4]]), "fill": col}])
	return _reset_icon


## Fade to black, switch scene, fade back in. The overlay lives on the root
## viewport, so it survives the scene change.
static func fade_change_scene(path: String, duration := 0.35) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP  # no clicks mid-transition
	layer.add_child(black)
	tree.root.add_child(layer)
	var t := layer.create_tween()
	t.tween_property(black, "color:a", 1.0, duration)
	await t.finished
	tree.paused = false
	await switch_scene(path)
	await tree.process_frame
	await tree.process_frame
	var t2 := layer.create_tween()
	t2.tween_property(black, "color:a", 0.0, duration)
	await t2.finished
	layer.queue_free()


## The scene changed to `path` over several frames: the old one freed first
## (thousands of nodes leaving: a few ms a frame), then the new one made
## (change_scene_to_file does both in one long frame) - and a scene that
## builds itself a piece a frame (`staging` is on while it enters the tree:
## the space scene, main.gd) waited for until it's all there (build_settled).
static var staging := false

static func switch_scene(path: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	var old := tree.current_scene
	if old != null:
		tree.current_scene = null   # (none for a few frames: what asks for it copes with none)
		await dismantle(old)
	await tree.process_frame
	var ps: PackedScene = load(path)
	var n := ps.instantiate()
	staging = true   # (a scene that builds itself a piece a frame does so now: main.gd)
	tree.root.add_child(n)
	staging = false
	tree.current_scene = n
	var waited := 0
	while is_instance_valid(n) and n.has_method("build_settled") and not n.build_settled() and waited < 600:
		await tree.process_frame
		waited += 1
	return n


## Frees a scene a few milliseconds a frame (a planet's 5000+ nodes freed at
## once: an 80 ms frame): it stops and hides first, then goes node by node
## from the leaves up (the last child's last child... first) - and the node
## itself last. Await it.
static func dismantle(n: Node, budget_us := 5000) -> void:
	if not is_instance_valid(n):
		return
	if not n.is_inside_tree():
		# (out of the tree - its parent being taken away, say: freed the safe
		# way, at the end of the frame - freeing its pieces now, mid-removal,
		# was a double free)
		if not n.is_queued_for_deletion():
			n.queue_free()
		return
	var tree := n.get_tree()
	n.process_mode = Node.PROCESS_MODE_DISABLED
	if n is CanvasItem:
		(n as CanvasItem).visible = false
	for l in n.find_children("*", "CanvasLayer", true, false):
		(l as CanvasLayer).visible = false
	# (freed from the next frame: a piece may be mid-call now - the button or
	# signal that started this - and a node can't be freed while it is)
	await tree.process_frame
	if not is_instance_valid(n) or not n.is_inside_tree():
		if is_instance_valid(n) and not n.is_queued_for_deletion():
			n.queue_free()
		return
	var t0 := Time.get_ticks_usec()
	while is_instance_valid(n) and n.is_inside_tree() and n.get_child_count() > 0:
		var piece := n.get_child(n.get_child_count() - 1)
		while piece.get_child_count() > 0:   # (from the leaves up: no one free is big)
			piece = piece.get_child(piece.get_child_count() - 1)
		piece.free()
		if Time.get_ticks_usec() - t0 > budget_us:
			await tree.process_frame
			t0 = Time.get_ticks_usec()
	# (the node itself at the frame's end: it may be the one that asked for this,
	# mid-call - a surface taking itself apart - and its pieces are gone by now)
	if is_instance_valid(n) and not n.is_queued_for_deletion():
		n.queue_free()


## Like fade_change_scene, to a scene already built (e.g. a planet surface
## prebuilt in the background): it's taken out of its current parent.
static func fade_change_scene_to_node(node: Node, duration := 0.35) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(black)
	tree.root.add_child(layer)
	var t := layer.create_tween()
	t.tween_property(black, "color:a", 1.0, duration)
	await t.finished
	tree.paused = false
	if node.get_parent() == tree.root:
		# Already in the tree (built there): made the scene where it is - no
		# leaving and entering the tree again - and the old scene freed.
		var old := tree.current_scene
		tree.current_scene = node
		if old != null and old != node:
			dismantle(old, 2000)   # (a little a frame, under the fade - little: the new scene's first frames are busy)
	else:
		if node.get_parent():
			node.get_parent().remove_child(node)
		tree.change_scene_to_node(node)
	await tree.process_frame
	if node.has_method("show_world"):
		node.show_world()
	await tree.process_frame
	await tree.process_frame
	# (a world that draws itself in over a few frames: black until it's there)
	var waited := 0
	while is_instance_valid(node) and node.has_method("world_settled") and not node.world_settled() and waited < 60:
		await tree.process_frame
		waited += 1
	var t2 := layer.create_tween()
	t2.tween_property(black, "color:a", 0.0, duration)
	await t2.finished
	layer.queue_free()


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## For things that animate by redrawing: true (and the clock reset) when it's
## time for the next picture - at most `hz` a second, and only while it can be
## seen. Each redraw of a hundred little animations every frame adds up at
## 240 FPS; their looks don't change faster than this.
##   if UI.redraw_due(self, 60.0): queue_redraw()
## The middle mouse button clicked (pressed and let go without dragging):
## every view that zooms with the wheel resets its zoom on it. Call with
## every mouse button event; true on the release of such a click. (Views
## that pan with a middle drag keep panning: a drag isn't a click.)
static func middle_click(n: Object, mb: InputEventMouseButton) -> bool:
	if mb.button_index != MOUSE_BUTTON_MIDDLE:
		return false
	if mb.pressed:
		n.set_meta("_mid_at", [mb.position, Time.get_ticks_msec()])
		return false
	var at: Variant = n.get_meta("_mid_at", null)
	if at != null:
		n.remove_meta("_mid_at")
	return at != null and mb.position.distance_to(at[0]) < 6.0 and Time.get_ticks_msec() - int(at[1]) < 600


## Whether `n` (a thing in the world) is on the screen or within `margin` px of
## it - things drawn round their own position, no bigger than that.
static func near_view(n: CanvasItem, margin := 300.0) -> bool:
	var p := n.get_global_transform_with_canvas().origin
	var size := n.get_viewport_rect().size
	return p.x > -margin and p.y > -margin and p.x < size.x + margin and p.y < size.y + margin


static func redraw_due(ci: CanvasItem, hz := 60.0) -> bool:
	if not ci.is_visible_in_tree():
		return false
	var now := Time.get_ticks_usec()
	var period := int(1e6 / hz)
	if not ci.has_meta("_redrawn_at"):
		# (A random phase each: not all of them redrawing in the same frame.)
		ci.set_meta("_redrawn_at", now - randi() % period)
		return true
	var last: int = ci.get_meta("_redrawn_at")
	if now - last < period:
		return false
	ci.set_meta("_redrawn_at", last + period * maxi(1, (now - last) / period))   # (keeps its phase)
	return true
