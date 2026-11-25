extends VBoxContainer
## The mesh editor's shape browser (the Shapes tab of its left panel): the shape
## library as a grid of pictures - each shape drawn once in the background as a
## turntable (mesh_thumbs.gd, kept on disk by its recipe), turning while the mouse
## is on it - with its name under it; categories as tabs, a search box. Click a
## shape: picked (its parameters in the SHAPE panel); double-click: added to the
## model; drag it into the 3D view: added where it's dropped.

signal picked(id: String)
signal activated(id: String)

const ShapeLibrary := preload("res://scripts/editor/mesh/shape_library.gd")

var lib: ShapeLibrary
var thumbs: Node
var cat := ""
var list: ItemList
var search: LineEdit
var _cats: HFlowContainer
var _cat_btns := {}
var _look: Material = preload("res://scripts/editor/mesh/mesh_io.gd").preset(4)   # (painted armour: the pictures' look)


func setup(library: ShapeLibrary, thumb_maker: Node) -> void:
	lib = library
	thumbs = thumb_maker
	thumbs.made.connect(_made)


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	search = LineEdit.new()
	search.name = "ShapeSearch"
	search.placeholder_text = "Find a shape..."
	search.add_theme_font_size_override("font_size", 14)
	search.clear_button_enabled = true
	search.tooltip_text = EditorIcons.tip("Find a shape", "", "Narrows the shapes to those whose name or category has these words.")
	search.text_changed.connect(func(_t): refill())
	add_child(search)
	_cats = HFlowContainer.new()
	_cats.add_theme_constant_override("h_separation", 4)
	_cats.add_theme_constant_override("v_separation", 4)
	add_child(_cats)
	list = ItemList.new()
	list.name = "ShapeList"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.focus_mode = Control.FOCUS_NONE
	list.add_theme_font_size_override("font_size", 13)
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.max_columns = 0
	list.fixed_icon_size = Vector2i(56, 56)
	list.fixed_column_width = 74
	list.same_column_width = true
	list.max_text_lines = 2
	list.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	list.item_selected.connect(func(i): picked.emit(str(list.get_item_metadata(i))))
	list.item_activated.connect(func(i): activated.emit(str(list.get_item_metadata(i))))
	list.set_drag_forwarding(_drag, Callable(), Callable())
	add_child(list)
	TurntableHover.attach(list, func(meta) -> Array: return thumbs.frames(_key(str(meta))) if thumbs else [])
	fill_cats()


## The category tabs (All, each category of the library).
func fill_cats() -> void:
	for c in _cats.get_children():
		c.queue_free()
	_cat_btns.clear()
	if lib == null:
		return
	for c in [""] + lib.categories:
		var b := Button.new()
		b.text = "All" if c == "" else str(c)
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.name = "Cat_" + (b.text.validate_node_name())
		b.tooltip_text = EditorIcons.tip("Category: " + b.text, "", "Shows %s." % ("every shape" if c == "" else "the shapes of this category"))
		b.button_pressed = c == cat
		b.pressed.connect(set_cat.bind(c))
		_cat_btns[c] = b
		_cats.add_child(b)
	refill()


func set_cat(c: String) -> void:
	cat = c
	for k in _cat_btns:
		(_cat_btns[k] as Button).set_pressed_no_signal(k == c)
	refill()


func _key(id: String) -> String:
	return ShapeLibrary.key_of(lib.entry(id)) if lib else ""


## The grid again (the library, the category or the search changed).
func refill() -> void:
	if lib == null or list == null:
		return
	var keep := selected()
	thumbs.clear_queue()
	list.clear()
	for id in lib.ids(cat, search.text if search else ""):
		var e := lib.entry(id)
		var k := ShapeLibrary.key_of(e)
		var tex: Texture2D = thumbs.get_thumb(k)
		if tex == null:
			var ec := e.duplicate(true)
			thumbs.ask_mesh(k, func():
				var m := ShapeLibrary.mesh_of(ec)
				if m and m.get_surface_count() > 0:
					m.surface_set_material(0, _look)
				return m)
		var i := list.add_item(str(e.get("name", id)), tex if tex else EditorIcons.get_icon("m_shapes"))
		list.set_item_metadata(i, id)
		var gen := str(e.get("gen", ""))
		var glabel: String = "a mesh of its own" if gen == "mesh" else str(load("res://scripts/editor/mesh/shapes.gd").GENS.get(gen, {}).get("label", gen))
		list.set_item_tooltip(i, "%s\n%s  ·  %s%s\nClick: its parameters (the SHAPE panel) · double-click: add it · drag it into the view: add it there" % [
			e.get("name", id), e.get("cat", ""), glabel, "" if e.get("builtin", false) else "  ·  yours"])
		if not e.get("builtin", false):
			list.set_item_custom_fg_color(i, Color(0.55, 1.0, 0.6))
		if id == keep:
			list.select(i)


func selected() -> String:
	if list == null:
		return ""
	var s := list.get_selected_items()
	return str(list.get_item_metadata(s[0])) if not s.is_empty() else ""


func select_id(id: String) -> void:
	for i in list.item_count:
		if str(list.get_item_metadata(i)) == id:
			list.select(i)
			list.ensure_current_is_visible()
			return


func _made(key: String, tex: Texture2D) -> void:
	if list == null or not key.begins_with("shape"):
		return
	for i in list.item_count:
		if _key(str(list.get_item_metadata(i))) == key:
			list.set_item_icon(i, tex)


## Dragging a shape out of the grid (into the 3D view): {"mesh_shape": id}, its picture under the mouse.
func _drag(at: Vector2) -> Variant:
	var i := list.get_item_at_position(at, true)
	if i < 0:
		return null
	var id := str(list.get_item_metadata(i))
	var pv := TextureRect.new()
	pv.texture = list.get_item_icon(i)
	pv.custom_minimum_size = Vector2(64, 64)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.modulate.a = 0.85
	set_drag_preview(pv)
	return {"mesh_shape": id}
