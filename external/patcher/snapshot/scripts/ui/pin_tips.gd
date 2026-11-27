class_name PinTips
extends CanvasLayer
## The editor screens' tooltips. It takes over every tooltip under it (a
## control's tooltip_text, or a "tip_fn" meta Callable(local_pos) -> String
## for per-item tips), so Godot's own tooltip never shows, and draws its own:
##   - after HOVER seconds over a control: its tooltip (title, shortcut,
##     description) with a bar filling toward pinning;
##   - after PIN more seconds: the tooltip pins - it stays (and can be
##     clicked) until its ✕ is pressed, it's right-clicked, you click
##     outside it, or another tooltip opens;
##   - every tooltip links to the editor documentation (EditorDocs): the
##     section its title is about and the screen's own section.
## Tooltip text format: "Title      [keys]\nDescription..." (EditorIcons.tip).

const HOVER := 0.45
const PIN := 12.0                   # seconds of hovering (after it shows) until it pins
const WIDTH := 460.0
const PIC := 280.0                  # an item's picture in its tooltip
const TipView := preload("res://scripts/ui/tip_view.gd")

## The documentation section for this screen (always linked), and its book.
var screen_doc := "overview"
var book := EditorDocs.FILE
var _text := ""                     # the tooltip under the mouse
var _t := 0.0
var _panel: PanelContainer
var _bar: ColorRect
var _pinned_text := ""             # don't re-show the one just pinned until the mouse leaves
var _src: Control                   # the control the tooltip belongs to
var _used: Control                  # just clicked: no tooltip for it until the mouse leaves it


## book: EditorDocs.FILE (editor screens) or EditorDocs.GAME (the game). The
## editor's take precedence while they're shown (the level editor inside a planet).
static func install(owner: Node, doc: String, book_file := EditorDocs.FILE) -> PinTips:
	var p := PinTips.new()
	p.screen_doc = doc
	p.book = book_file
	if book_file == EditorDocs.FILE:
		p.add_to_group("pin_tips_editor")
	owner.add_child(p)
	return p


## In the game: F1 opens the guide at the page this returns (paused or not).
var f1_page := Callable()


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	# Typing hides the tooltip that's waiting or showing (pinned ones stay).
	if event is InputEventKey and event.pressed and not (event as InputEventKey).keycode == KEY_F1:
		var f := get_viewport().gui_get_focus_owner()
		if f is LineEdit or f is TextEdit:
			_hide()
			_t = 0.0
	# Pinned tooltips close on a right-click (anywhere), or a click outside them.
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		# Using a control: its tooltip goes away until the mouse leaves it.
		_hide()
		_t = 0.0
		if _src != null and is_instance_valid(_src) and _src.get_global_rect().has_point(mb.position):
			_used = _src
	if mb and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
		var on_tip := false
		for n in get_children():
			if not n.is_in_group("pin_tip") or n == _panel or n.is_queued_for_deletion():
				continue
			var inside: bool = (n as Control).get_global_rect().has_point(mb.position)
			if mb.button_index == MOUSE_BUTTON_RIGHT or not inside:
				n.queue_free()
				_pinned_text = ""
			if inside:
				on_tip = true
		if on_tip and mb.button_index == MOUSE_BUTTON_RIGHT:
			get_viewport().set_input_as_handled()   # (that right-click was for the tooltip)
		return
	var k := event as InputEventKey
	if f1_page.is_valid() and k and k.pressed and not k.echo and k.keycode == KEY_F1:
		var page: String = f1_page.call()
		if page != "":
			EditorDocs.open(self, page, book)
			get_viewport().set_input_as_handled()


## The tooltip of the control under the mouse (taking it over from Godot).
## True while you're busy with the GUI: a drop-down list or menu is open,
## or a mouse button is held (dragging a slider, scrolling, drawing...).
func _busy() -> bool:
	for w in get_viewport().get_embedded_subwindows():
		if w.visible and w is Popup:
			return true
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) \
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)


func _hovered_tip() -> String:
	var vp := get_viewport()
	if _busy():
		return ""
	var c := vp.gui_get_hovered_control()
	# Typing into a field: no tooltip for it (nor for the spin box around it).
	var focus := vp.gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit:
		var n: Node = c
		while n != null:
			if n == focus or n == focus.get_parent() and n is SpinBox:
				return ""
			n = n.get_parent()
	set_meta("pic_fn", null)
	set_meta("view_fn", null)
	while c != null:
		if _is_ours(c):
			return ""
		if c is ItemList and not c.has_meta("tip_fn"):
			# (a list's items: each its own tooltip, its picture big - the list's own never over them; it's on
			# the list's tab)
			var il := c as ItemList
			if il.tooltip_text != "":
				il.tooltip_text = ""
			var i := il.get_item_at_position(il.get_local_mouse_position(), true)
			if i < 0 or il.get_item_tooltip(i) == "":
				return ""
			if il.is_item_tooltip_enabled(i):
				il.set_item_tooltip_enabled(i, false)   # (Godot's own: not as well)
			_src = c
			var pf: Callable = (func(): return (il.get_meta("tip_pic") as Callable).call(i)) if il.has_meta("tip_pic") else (func(): return il.get_item_icon(i))
			set_meta("pic_fn", pf)
			if il.has_meta("tip_view"):
				set_meta("view_fn", func(): return (il.get_meta("tip_view") as Callable).call(i))
			return il.get_item_tooltip(i)
		if c.has_meta("tip_fn"):
			var at := c.get_local_mouse_position()
			var t: String = (c.get_meta("tip_fn") as Callable).call(at)
			if t != "":
				_src = c
				var cc := c
				if c.has_meta("tip_pic"):
					set_meta("pic_fn", func(): return (cc.get_meta("tip_pic") as Callable).call(at))
				if c.has_meta("tip_view") and (cc.get_meta("tip_view") as Callable).call(at, true) == true:
					set_meta("view_fn", func(): return (cc.get_meta("tip_view") as Callable).call(at, false))
				return t
			if c is Tree or c is ItemList:
				return ""   # (between its rows: nothing - not the list's own)
		if c.tooltip_text != "":
			c.set_meta("tip", c.tooltip_text)
			c.tooltip_text = ""   # (Godot's tooltip would show it too)
		if c.has_meta("tip") and str(c.get_meta("tip")) != "":
			_src = c
			return str(c.get_meta("tip"))
		c = c.get_parent() as Control
	return ""


func _is_ours(c: Control) -> bool:
	var n: Node = c
	while n != null:
		if n == self or n.is_in_group("pin_tip") or n.is_in_group("archive_window"):
			return true
		n = n.get_parent()
	return false


func _process(delta: float) -> void:
	var host := get_parent() as CanvasItem
	var yield_to_editor := false
	if book != EditorDocs.FILE:
		for o in get_tree().get_nodes_in_group("pin_tips_editor"):
			var oh := o.get_parent() as CanvasItem
			if oh and oh.is_visible_in_tree():
				yield_to_editor = true
	if host and not host.is_visible_in_tree() or yield_to_editor:
		_text = ""
		_hide()
		return
	# Pinned tooltips close with the screen their control was on.
	for n in get_children():
		if n.is_in_group("pin_tip") and n != _panel and n.has_meta("src"):
			var sc: Variant = n.get_meta("src")
			if not is_instance_valid(sc) or not (sc as Control).is_visible_in_tree():
				n.queue_free()
	var tip := _hovered_tip()
	if _used != null and (not is_instance_valid(_used) or _src != _used or tip == ""):
		if not _busy():
			_used = null    # the mouse left the control you used
	if _used != null and is_instance_valid(_used) and _src == _used:
		tip = ""
	if tip != _text:
		_text = tip
		_t = 0.0
		_hide()
		if tip != _pinned_text:
			_pinned_text = ""
	if _text == "" or _text == _pinned_text:
		return
	_t += delta
	if _t >= HOVER and _panel == null:
		_close_pinned()   # a new tooltip replaces the one pinned before
		_panel = _make(_text, false)
		_place(_panel)
	_update_pics()
	if _panel:
		var k := clampf((_t - HOVER) / PIN, 0.0, 1.0)
		_bar.size.x = (_panel.size.x - 20.0) * k
		if k >= 1.0:
			_pin(_panel)
			_pinned_text = _text
			_panel = null


## How many of the screen's pixels one of the interface's is (a big screen, the interface scaled up: 2...).
static func screen_scale(n: Node) -> float:
	var w := n.get_tree().root
	var s := w.content_scale_factor
	if w.content_scale_size.y > 0 and w.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
		s *= float(w.size.y) / float(w.content_scale_size.y)
	return maxf(s, 1.0)


## Tooltips' pictures: the item's better picture once it's made (a big one drawn in the background).
func _update_pics() -> void:
	for n in get_children():
		if not n.has_meta("pic"):
			continue
		var pic = n.get_meta("pic")
		if not is_instance_valid(pic):
			continue
		var fn: Callable = (pic as Node).get_meta("pic_fn")
		if not fn.is_valid():
			continue
		var tex = fn.call()
		if tex is Texture2D and tex != (pic as TextureRect).texture:
			(pic as TextureRect).texture = tex
			(pic as Control).visible = true


## Closes every pinned tooltip.
func _close_pinned() -> void:
	for n in get_children():
		if n != _panel and n.is_in_group("pin_tip"):
			n.queue_free()


func _hide() -> void:
	if _panel:
		_panel.queue_free()
		_panel = null


## Shrinks a panel to its content once its text has wrapped (rich text
## measures its height only after it knows its width).
func _fit(p: Control) -> void:
	for i in 2:
		await get_tree().process_frame
		if not is_instance_valid(p):
			return
		p.reset_size()


## Shows a pinned tooltip once it has shrunk to its content.
func _reveal(p: Control) -> void:
	await _fit(p)
	if is_instance_valid(p):
		p.modulate.a = 1.0


func _place(p: Control) -> void:
	await _fit(p)
	if not is_instance_valid(p):
		return
	var vp := get_viewport().get_visible_rect().size
	var m := get_viewport().get_mouse_position() + Vector2(18, 22)
	if m.x + p.size.x > vp.x - 8:
		m.x = vp.x - 8 - p.size.x
	if m.y + p.size.y > vp.y - 8:
		m.y = get_viewport().get_mouse_position().y - p.size.y - 12
	p.position = m.max(Vector2(8, 8))
	p.modulate.a = 1.0


## Parses "Title      [keys]\nbody" -> [title, keys, body].
static func parse(tip: String) -> Array:
	var lines := tip.split("\n", true, 1)
	var head := lines[0]
	var keys := ""
	var i := head.find("      [")
	if i >= 0 and head.ends_with("]"):
		keys = head.substr(i + 7, head.length() - i - 8)
		head = head.substr(0, i)
	return [head.strip_edges(), keys, lines[1] if lines.size() > 1 else ""]


func _make(tip: String, pinned: bool) -> PanelContainer:
	var parts := parse(tip)
	var p := PanelContainer.new()
	p.add_to_group("pin_tip")
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NeonTheme.BG, 0.97)
	sb.border_color = Color(NeonTheme.HEAD, 0.85) if not pinned else Color(1.0, 0.75, 0.3, 0.95)
	sb.set_border_width_all(2 if pinned else 1)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(WIDTH, 0)
	p.modulate.a = 0.0   # shown once it's laid out and in place (see _place, _pin)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE if not pinned else Control.MOUSE_FILTER_STOP
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	var t := Label.new()
	t.text = parts[0]
	t.add_theme_font_override("font", NeonTheme.heavy_font())
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", NeonTheme.HEAD)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(t)
	if parts[1] != "":
		var k := Label.new()
		k.text = " " + parts[1] + " "
		k.add_theme_font_size_override("font_size", 14)
		k.add_theme_color_override("font_color", Color(0.08, 0.06, 0.02))
		var ks := StyleBoxFlat.new()
		ks.bg_color = Color(1.0, 0.8, 0.4)
		ks.set_corner_radius_all(4)
		ks.set_content_margin_all(2)
		k.add_theme_stylebox_override("normal", ks)
		k.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(k)
	if pinned:
		var x := CloseX.new()
		x.pressed.connect(p.queue_free)
		head.add_child(x)
	var pf = get_meta("pic_fn") if has_meta("pic_fn") else null
	var vf = get_meta("view_fn") if has_meta("view_fn") else null
	if vf is Callable and (vf as Callable).is_valid():
		# (the item itself, turning slowly - drawn at the screen's pixels)
		var tv: TextureRect = TipView.new()
		tv.name = "View"
		tv.custom_minimum_size = Vector2(PIC, PIC)
		tv.source = vf
		tv.fallback = (pf as Callable).call() if pf is Callable and (pf as Callable).is_valid() else null
		v.add_child(tv)
		p.set_meta("view_fn", vf)
		p.set_meta("pic_fn", pf)
	elif pf is Callable and (pf as Callable).is_valid():
		# (an item's picture, big: what it is at a glance - a better one swapped in when it's made)
		var pic := TextureRect.new()
		pic.name = "Pic"
		pic.custom_minimum_size = Vector2(PIC, PIC)
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.texture = (pf as Callable).call()
		pic.set_meta("pic_fn", pf)
		pic.visible = pic.texture != null
		if pic.texture:
			# (never bigger than its own pixels on the screen: not blurred)
			var sc := screen_scale(self)
			var px := minf(PIC, minf(pic.texture.get_width(), pic.texture.get_height()) / sc)
			pic.custom_minimum_size = Vector2(px, px)
		v.add_child(pic)
		p.set_meta("pic", pic)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(WIDTH - 20, 0)
	body.add_theme_font_size_override("normal_font_size", 14)
	body.add_theme_color_override("default_color", NeonTheme.TEXT)
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE if not pinned else Control.MOUSE_FILTER_STOP
	body.text = str(parts[2]).replace("[", "[lb]")
	v.add_child(body)
	# Links to the documentation: the topic, and this screen's section.
	EditorDocs.use(book)
	var links := []
	var topic := EditorDocs.topic(parts[0])
	for id in [topic, screen_doc, "tooltips" if book == EditorDocs.FILE else "guide-tooltips"]:
		if id != "" and EditorDocs.has(id) and not id in links:
			links.append(id)
	var docs := RichTextLabel.new()
	docs.bbcode_enabled = true
	docs.fit_content = true
	docs.scroll_active = false
	docs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	docs.custom_minimum_size = Vector2(WIDTH - 20, 0)
	docs.add_theme_font_size_override("normal_font_size", 14)
	docs.mouse_filter = Control.MOUSE_FILTER_IGNORE if not pinned else Control.MOUSE_FILTER_STOP
	var parts_l := links.map(func(id): return "[url=doc:%s]%s[/url]" % [id, EditorDocs.title(id)])
	docs.text = "[color=#8fa3b8]Documentation:[/color]  [color=#7fd6ff]%s[/color]" % "   ·   ".join(parts_l)
	if not pinned:
		docs.text += "\n[color=#6f7f90][i]Keep hovering to pin this tooltip and click its links.[/i][/color]"
	var bk := book
	docs.meta_clicked.connect(func(m): if str(m).begins_with("doc:"): EditorDocs.open(self, str(m).substr(4), bk))
	v.add_child(docs)
	if not pinned:
		var track := Control.new()
		track.custom_minimum_size = Vector2(0, 3)
		track.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bar = ColorRect.new()
		_bar.color = Color(1.0, 0.75, 0.3)
		_bar.size = Vector2(0, 3)
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(_bar)
		v.add_child(track)
	add_child(p)
	return p


## Turns the hovering tooltip into a pinned one (same place).
func _pin(p: PanelContainer) -> void:
	var at := p.position
	var tip := _text
	if p.has_meta("pic") and is_instance_valid(p.get_meta("pic")):
		set_meta("pic_fn", (p.get_meta("pic") as Node).get_meta("pic_fn"))
	if p.has_meta("view_fn"):
		set_meta("view_fn", p.get_meta("view_fn"))
		set_meta("pic_fn", p.get_meta("pic_fn"))
	p.queue_free()
	var q := _make(tip, true)
	q.position = at
	q.set_meta("src", _src)
	_reveal(q)
	# Pinned tooltips can be dragged by their title.
	q.gui_input.connect(func(e):
		if e is InputEventMouseMotion and e.button_mask & MOUSE_BUTTON_MASK_LEFT:
			q.position += e.relative)


## The pinned tooltip's close button: a red ✕ that slowly blinks, with an
## orange glow circling around it. Brighter when hovered.
class CloseX extends Control:
	signal pressed
	const BLINK := 1.6               # seconds per blink
	const ORBIT := 2.4               # seconds per turn of the glow
	var _t := 0.0
	var _hover := false
	var _box: StyleBoxFlat

	func _ready() -> void:
		custom_minimum_size = Vector2(34, 34)
		# A bluish button face, like the rest of the GUI.
		_box = StyleBoxFlat.new()
		_box.bg_color = NeonTheme.BG_LIGHT
		_box.border_color = Color(NeonTheme.HEAD, 0.75)
		_box.set_border_width_all(1)
		_box.set_corner_radius_all(6)
		_box.shadow_color = Color(NeonTheme.CYAN, 0.25)
		_box.shadow_size = 3
		size_flags_vertical = SIZE_SHRINK_CENTER
		mouse_filter = MOUSE_FILTER_STOP
		mouse_default_cursor_shape = CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _hover = true)
		mouse_exited.connect(func(): _hover = false)

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var c := size / 2.0
		var blink := 0.5 + 0.5 * sin(_t * TAU / BLINK)      # 0..1, slow
		_box.bg_color = NeonTheme.BG_LIGHT if _hover else NeonTheme.BG_LIGHT
		_box.border_color = Color(NeonTheme.HEAD, 1.0 if _hover else 0.75)
		draw_style_box(_box, Rect2(Vector2(1, 1), size - Vector2(2, 2)))
		var r := 11.0
		# Soft red halo that breathes with the blink.
		for i in 4:
			draw_circle(c, r + 2.0 - i * 2.5, Color(1.0, 0.15, 0.1, 0.05 + 0.05 * blink))
		# The orange glow orbiting: a bright head with a fading tail.
		var a0 := _t * TAU / ORBIT
		var n := 14
		for i in n:
			var k := float(i) / n
			var a := a0 - k * 2.2
			var col := Color(1.0, 0.55 + 0.25 * (1.0 - k), 0.15, (1.0 - k) * 0.85)
			draw_circle(c + Vector2.from_angle(a) * r, 2.6 * (1.0 - k * 0.7), col)
		draw_circle(c + Vector2.from_angle(a0) * r, 4.5, Color(1.0, 0.7, 0.3, 0.35))
		# The ✕, blinking between deep and bright red.
		var x := lerpf(0.45, 1.0, blink) if not _hover else 1.0
		var red := Color(1.0, 0.18, 0.12).lerp(Color(1.0, 0.45, 0.4), 0.0 if not _hover else 0.5) * Color(x, x, x, 1.0)
		red.a = lerpf(0.55, 1.0, blink) if not _hover else 1.0
		var d := 5.5
		for w in [[5.0, Color(red, red.a * 0.35)], [2.6, red]]:
			draw_line(c + Vector2(-d, -d), c + Vector2(d, d), w[1], w[0], true)
			draw_line(c + Vector2(d, -d), c + Vector2(-d, d), w[1], w[0], true)
