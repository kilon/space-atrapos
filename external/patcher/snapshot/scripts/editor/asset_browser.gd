class_name AssetBrowser
extends PanelContainer
## The Library's asset browser: every asset of the game (AssetCatalog), sorted
## by who it belongs to. Left: a search box and a tree - each empire, the
## Independents, the Sea Peoples, you, the monsters, the wildlife, the galaxy
## and the interface, with their categories (Ships, Stations, Characters,
## Buildings...) and counts. Middle: the chosen category (or the search's
## hits) as thumbnail cards. Right: the selected asset - a big preview, what
## it is, its file - and "View live", which opens the Library's live room
## showing it (animated; planets, suns and nebulae editable there).
## Double-click a card: view it live.

signal view_live(room: String, spot: String)

var _tree: Tree
var _search: LineEdit
var _head: Label
var _grid: HFlowContainer
var _scroll: ScrollContainer
var _preview: TextureRect
var _swatch: Control
var _title: Label
var _sub: Label
var _info: Label
var _file: Label
var _live: Button
var _sel := {}                      # the selected entry
var _cur: Array = []                # the entries shown
var _cards := {}                    # key -> card button


func _ready() -> void:
	add_theme_stylebox_override("panel", UI.panel_style(Color(NeonTheme.CYAN, 0.7)))
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 12)
	add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	m.add_child(row)

	# Left: search and the owners' tree.
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 320
	left.add_theme_constant_override("separation", 8)
	row.add_child(left)
	_search = LineEdit.new()
	_search.placeholder_text = "Search every asset..."
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _show_search())
	left.add_child(_search)
	_tree = Tree.new()
	_tree.hide_root = true
	_tree.size_flags_vertical = SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_tree)
	left.add_child(_tree)
	var root := _tree.create_item()
	var first: TreeItem = null
	for o in AssetCatalog.owners():
		var oi := _tree.create_item(root)
		var n := 0
		for c in o["categories"]:
			n += c["entries"].size()
		oi.set_text(0, "%s  (%d)" % [o["name"], n])
		oi.set_custom_color(0, Color(o["color"]).lightened(0.25))
		oi.set_metadata(0, {"owner": o})
		oi.set_icon(0, _dot(o["color"]))
		for c in o["categories"]:
			# A category: its icon and its name (the count in the tooltip).
			var ci := _tree.create_item(oi)
			ci.set_text(0, str(c["name"]))
			var ic: Array = category_icon(c["name"])
			ci.set_icon(0, EditorIcons.get_icon(ic[0]))
			ci.set_icon_modulate(0, ic[1])
			ci.set_tooltip_text(0, "%s  (%d)" % [c["name"], c["entries"].size()])
			ci.set_metadata(0, {"owner": o, "category": c})
			if first == null:
				first = ci
		oi.collapsed = o["id"] in ["wildlife", "galaxy"]

	# Middle: the cards.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 8)
	row.add_child(mid)
	_head = UI.label("", 20, NeonTheme.HEAD)
	_head.add_theme_font_override("font", NeonTheme.heavy_font())
	mid.add_child(_head)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mid.add_child(_scroll)
	_grid = HFlowContainer.new()
	_grid.size_flags_horizontal = SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_scroll.add_child(_grid)

	# Right: the selected asset.
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 400
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	var pv := PanelContainer.new()
	var pvs := StyleBoxFlat.new()
	pvs.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	pvs.border_color = Color(NeonTheme.CYAN, 0.35)
	pvs.set_border_width_all(1)
	pv.add_theme_stylebox_override("panel", pvs)
	pv.custom_minimum_size = Vector2(400, 320)
	right.add_child(pv)
	_preview = TextureRect.new()
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	pv.add_child(_preview)
	_swatch = _disc_control(Color(0, 0, 0, 0))
	pv.add_child(_swatch)
	_title = UI.label("", 22, Color.WHITE)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_title)
	_sub = UI.label("", 15, NeonTheme.HEAD)
	right.add_child(_sub)
	_info = UI.label("", 14, UI.TEXT_DIM)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_info)
	_file = UI.label("", 14, Color(UI.TEXT_DIM, 0.8))
	_file.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	right.add_child(_file)
	_live = UI.button("View live", _open_live, 17)
	_live.custom_minimum_size.y = 42
	_live.tooltip_text = EditorIcons.tip("View live", "Double-click a card",
		"Opens the Library's live room with this asset in it: animated as in the game - and planets, suns and nebulae editable there.")
	right.add_child(_live)
	if first:
		first.select(0)
		_on_tree()


## A category's icon and its tint: [EditorIcons name, colour].
static func category_icon(cat: String) -> Array:
	var white := Color.WHITE
	var tint := {"forest": Color(0.5, 0.95, 0.5), "ice": Color(0.6, 0.85, 1.0), "volcanic": Color(1.0, 0.5, 0.3), "gas giant": Color(1.0, 0.8, 0.45)}
	for k in tint:
		if cat.to_lower().contains(k):
			return ["terrain" if cat.begins_with("Terrain") else "neutral", tint[k]]
	return [{"Ships": "ships", "Ship": "ship", "Pilot": "characters", "Stations": "stations", "Station": "stations", "Characters": "characters", "Portraits": "npc",
		"Buildings": "buildings", "Furniture": "prop", "Effects": "effects", "Creatures of myth": "enemy",
		"Bosses": "enemy", "Planets": "planets", "Suns": "suns", "Nebulae": "nebulae", "Asteroids": "asteroid",
		"Jump gates": "star_tool", "Skies": "eye", "Widgets": "gui", "Interface": "gui", "Others": "neutral"}.get(cat, "zoo"),
		Color(1.0, 0.75, 0.5) if cat == "Bosses" else white]


## A small coloured dot (the owners' tree).
static func _dot(c: Color) -> Texture2D:
	var img := Image.create(14, 14, false, Image.FORMAT_RGBA8)
	for y in 14:
		for x in 14:
			var d := Vector2(x - 6.5, y - 6.5).length()
			img.set_pixel(x, y, Color(c, clampf(6.0 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


## A shaded disc in a colour (procedural assets: planets, suns, nebulae, asteroids).
static func _disc_control(c: Color) -> Control:
	var d := Control.new()
	d.set_meta("color", c)
	d.mouse_filter = MOUSE_FILTER_IGNORE
	d.draw.connect(func():
		var col: Color = d.get_meta("color")
		if col.a <= 0.0:
			return
		var r := minf(d.size.x, d.size.y) * 0.38
		var ctr := d.size / 2.0
		for i in 6:
			d.draw_circle(ctr, r * (1.35 - i * 0.05), Color(col, 0.04))
		d.draw_circle(ctr, r, col.darkened(0.45))
		d.draw_circle(ctr - Vector2(r, r) * 0.2, r * 0.78, col)
		d.draw_circle(ctr - Vector2(r, r) * 0.38, r * 0.3, col.lightened(0.3)))
	return d


func _on_tree() -> void:
	var it := _tree.get_selected()
	if it == null:
		return
	var md: Dictionary = it.get_metadata(0)
	_search.text = ""
	var entries := []
	var head := ""
	if md.has("category"):
		entries = md["category"]["entries"]
		head = "%s  ·  %s  (%d)" % [md["owner"]["name"].to_upper(), md["category"]["name"].to_upper(), entries.size()]
	else:
		for c in md["owner"]["categories"]:
			entries.append_array(c["entries"])
		head = "%s  ·  EVERYTHING  (%d)" % [md["owner"]["name"].to_upper(), entries.size()]
	_show(entries, head)


func _show_search() -> void:
	var q := _search.text.strip_edges().to_lower()
	if q == "":
		_on_tree()
		return
	var hits := []
	for t in AssetCatalog.all_entries():
		var e: Dictionary = t[2]
		if q in str(e["title"]).to_lower() or q in str(e["key"]).to_lower() or q in str(t[0]["name"]).to_lower():
			hits.append(e)
	_show(hits, "SEARCH  ·  \"%s\"  (%d)" % [_search.text.strip_edges(), hits.size()])


## Shows these entries as cards (the first one selected).
func _show(entries: Array, head: String) -> void:
	_head.text = head
	UI.clear(_grid)
	_cards = {}
	_cur = entries
	for e in entries:
		_grid.add_child(_card(e))
	_scroll.scroll_vertical = 0
	if not entries.is_empty():
		select(entries[0])
	else:
		select({})


func _card(e: Dictionary) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(160, 186)
	b.tooltip_text = "%s\n%s" % [e["title"], e["info"]]
	b.pressed.connect(func(): select(e))
	b.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.double_click and ev.button_index == MOUSE_BUTTON_LEFT:
			select(e)
			_open_live())
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	v.offset_left = 6
	v.offset_right = -6
	v.offset_top = 6
	v.offset_bottom = -6
	v.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(v)
	var tex := AssetCatalog.texture(e)
	if tex:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(148, 132)
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		v.add_child(tr)
	else:
		var d := _disc_control(e["swatch"] if e["swatch"].a > 0.0 else Color(0.4, 0.42, 0.5))
		d.custom_minimum_size = Vector2(148, 132)
		v.add_child(d)
	var l := UI.label(e["title"], 13, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.max_lines_visible = 2
	l.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(l)
	_cards[e["key"]] = b
	return b


## Selects an entry: its card lit, its preview and details on the right.
func select(e: Dictionary) -> void:
	_sel = e
	for k in _cards:
		_cards[k].set_pressed_no_signal(not e.is_empty() and k == e["key"])
	if e.is_empty():
		_preview.texture = null
		_swatch.set_meta("color", Color(0, 0, 0, 0))
		_swatch.queue_redraw()
		_title.text = "Nothing here"
		_sub.text = ""
		_info.text = ""
		_file.text = ""
		_live.disabled = true
		return
	var tex := AssetCatalog.texture(e)
	_preview.texture = tex
	_swatch.set_meta("color", e["swatch"] if tex == null else Color(0, 0, 0, 0))
	_swatch.queue_redraw()
	_title.text = e["title"]
	var size_txt := ("  ·  %d x %d px" % [tex.get_width(), tex.get_height()]) if tex else ""
	_sub.text = str(e["sub"]) + size_txt
	_info.text = e["info"]
	var t: String = e["tex"]
	_file.text = t if t.begins_with("res://") else (("data/sprites/%s.png" % t) if t != "" and not t.begins_with("type:") else "")
	_live.disabled = str(e["room"]) == ""
	_live.text = "View live  ·  %s" % str(e["room"]).capitalize() if not _live.disabled else "No live room"


func selected() -> Dictionary:
	return _sel


func _open_live() -> void:
	if not _sel.is_empty() and str(_sel["room"]) != "":
		view_live.emit(_sel["room"], _sel["spot"])


## Shows a category by its owner id and name (tests, LiveLink).
func open(owner_id: String, category := "") -> bool:
	var it := _tree.get_root().get_first_child()
	while it:
		var md: Dictionary = it.get_metadata(0)
		if md["owner"]["id"] == owner_id:
			if category == "":
				it.select(0)
				_on_tree()
				return true
			var c := it.get_first_child()
			while c:
				if c.get_metadata(0)["category"]["name"] == category:
					it.collapsed = false
					c.select(0)
					_on_tree()
					return true
				c = c.get_next()
		it = it.get_next()
	return false


func shown() -> Array:
	return _cur
