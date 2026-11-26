extends Control
## Labels over the planets of the current system: "LAND · NAME" buttons for
## landable planets, a plain name tag for the others. Planets are OrbitBody
## nodes in the world (group "planet_bodies"); each tag sits over its planet
## while the planet is on screen. Located signal sources (SignalBeacon) get
## an "ENTER · <signal>" button over them: it drops you into the site (from
## afar, you fly there first - main.request_site).

var main: Node
var _tags := {}   # OrbitBody -> Control (Button or Label)
var _enter := {}  # SignalBeacon -> Button


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE


func _make_tag(b: OrbitBody) -> Control:
	var tag: Control
	if b.landable:
		var btn := Button.new()
		btn.text = b.title.to_upper()
		btn.icon = EditorIcons.get_icon("land")
		btn.tooltip_text = EditorIcons.tip("Land on %s" % b.title, "", "%s\nAsks first, then your ship descends: walk around, meet the citizens, explore the buildings.\nClick your landed ship (or right-click > Leave planet) to return to orbit." % b.desc)
		btn.focus_mode = FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 15)
		# In the GUI palette (NeonTheme).
		btn.add_theme_stylebox_override("normal", _style(Color(NeonTheme.BG_LIGHT, 0.85), Color(NeonTheme.CYAN, 0.8)))
		btn.add_theme_stylebox_override("hover", _style(Color(NeonTheme.BG_LIGHT.lightened(0.1), 0.95), NeonTheme.CYAN.lightened(0.3)))
		btn.add_theme_stylebox_override("pressed", _style(Color(NeonTheme.BG_LIGHT.lightened(0.18), 0.95), NeonTheme.CYAN.lightened(0.3)))
		btn.add_theme_color_override("font_color", NeonTheme.CYAN.lightened(0.55))
		var pid := b.planet_id
		btn.pressed.connect(func(): main.request_land(pid))
		tag = btn
	else:
		var l := Label.new()
		l.text = b.title.to_upper()
		l.tooltip_text = b.desc
		l.add_theme_font_size_override("font_size", 14)
		l.add_theme_color_override("font_color", Color(0.85, 0.8, 0.7, 0.85))
		l.add_theme_constant_override("outline_size", 4)
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.mouse_filter = MOUSE_FILTER_IGNORE
		tag = l
	tag.visible = false
	add_child(tag)
	return tag


static func _style(bg: Color, border: Color) -> NeonBox:
	var s := NeonTheme.box(border, bg, 1, 6, 7)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 4
	s.content_margin_bottom = 4
	return s


func _process(_delta: float) -> void:
	if main == null:
		return
	var screen := get_viewport_rect().size
	# Keep labels out of the HUD: status panel (top-left), minimap and
	# objectives (top-right), event log and toolbar (bottom).
	var safe := Rect2(Vector2(340, 130), screen - Vector2(340 + 330, 130 + 250))   # (330: the minimap and its ring)
	_update_enter_buttons(safe)
	for b in get_tree().get_nodes_in_group("planet_bodies"):
		if not _tags.has(b):
			_tags[b] = _make_tag(b)
		var tag: Control = _tags[b]
		var xf: Transform2D = b.get_global_transform_with_canvas()
		var c: Vector2 = xf.origin
		var r: float = b.radius * xf.get_scale().x
		var disc := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0).grow(-r * 0.24)
		var visible_part := disc.intersection(safe)
		tag.visible = visible_part.size.x > 30.0 and visible_part.size.y > 20.0
		if tag.visible:
			if tag.size.x < 1.0:
				tag.reset_size()   # (once: laying it out every frame was most of this)
			tag.position = Vector2(visible_part.get_center().x - tag.size.x / 2.0, visible_part.position.y + 4.0)
			tag.position.x = clampf(tag.position.x, safe.position.x, safe.end.x - tag.size.x)


func _enter_button(b: SignalBeacon) -> Button:
	var btn := Button.new()
	btn.text = "ENTER  ·  " + b.title().to_upper()
	btn.icon = EditorIcons.get_icon("forward")
	btn.tooltip_text = EditorIcons.tip("Enter: %s" % SignalSites.title(b.sig), "", "%s\nDrops you into the signal source - a pocket of empty space where it plays out.\nFrom far away your ship flies to the beacon first. Leave from the panel at the top." % SignalSites.info(b.sig["kind"])["detail"])
	btn.focus_mode = FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 15)
	var c := b.color()
	btn.add_theme_stylebox_override("normal", _style(Color(NeonTheme.BG_LIGHT, 0.85), Color(c, 0.85)))
	btn.add_theme_stylebox_override("hover", _style(Color(NeonTheme.BG_LIGHT.lightened(0.1), 0.95), c.lightened(0.3)))
	btn.add_theme_stylebox_override("pressed", _style(Color(NeonTheme.BG_LIGHT.lightened(0.18), 0.95), c.lightened(0.3)))
	btn.add_theme_color_override("font_color", c.lightened(0.45))
	btn.pressed.connect(func(): main.request_site(b))
	btn.visible = false
	add_child(btn)
	return btn


func _update_enter_buttons(safe: Rect2) -> void:
	for b in _enter.keys():
		if not is_instance_valid(b):
			_enter[b].queue_free()
			_enter.erase(b)
	var in_site: bool = main.get("site") != null
	for b in get_tree().get_nodes_in_group("signal_beacons"):
		if not _enter.has(b):
			_enter[b] = _enter_button(b)
		var btn: Button = _enter[b]
		var c: Vector2 = b.get_global_transform_with_canvas().origin
		btn.visible = not in_site and b.active() and safe.has_point(c)
		if btn.visible:
			if btn.size.x < 1.0:
				btn.reset_size()
			btn.position = Vector2(c.x - btn.size.x / 2.0, c.y - 120.0)
