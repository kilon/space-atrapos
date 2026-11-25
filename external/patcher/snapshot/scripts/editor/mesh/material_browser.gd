extends VBoxContainer
## The mesh editor's material browser (the Materials tab of its left panel): the material
## library (material_library.gd) as a grid of balls - each drawn once in the background as a
## turntable (mesh_thumbs.gd, kept by the material's settings), turning while the mouse is on
## it - with its name under it; the groups (This model, Characters, Presets, Mine) as buttons,
## a search box, and New / Duplicate / Rename / Delete. Click one: picked (its settings in the
## MATERIAL panel); double-click: given to the selected surface (or faces); drag it onto a
## surface in the 3D view: given to that surface.

signal picked(id: String)
signal activated(id: String)
signal action(what: String)

const MaterialLibrary := preload("res://scripts/editor/mesh/material_library.gd")

var lib: MaterialLibrary
var thumbs: Node
var group := ""
var list: ItemList
var search: LineEdit
var _cats: HFlowContainer
var _cat_btns := {}
var _keys := {}          # id -> its picture's key (as last asked)


func setup(library: MaterialLibrary, thumb_maker: Node) -> void:
	lib = library
	thumbs = thumb_maker
	thumbs.made.connect(_made)


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	var tools := HFlowContainer.new()
	tools.add_theme_constant_override("h_separation", 2)
	tools.add_theme_constant_override("v_separation", 2)
	for t in [["new", "m_mat_new", "New material", "A new material of your own (in the Mine group), to edit in the MATERIAL panel - a character's\nkind when a character is open (only what the game keeps of it), else a full one."],
			["duplicate", "m_mat_duplicate", "Duplicate material", "A copy of the picked material as one of yours (Mine) - the way to change a built-in look."],
			["rename", "m_mat_rename", "Rename material", "A new name for the picked material (yours only - a character's materials keep their names:\nthe game finds them by name)."],
			["delete", "m_mat_delete", "Delete material", "Removes the picked material from the library (yours; a built-in look only in a mod, asked first).\nSurfaces that have it keep it."]]:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.name = "Mat_" + t[0]
		EditorIcons.dress(b, t[1], EditorIcons.tip(t[2], "", t[3]))
		b.text = ""
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.custom_minimum_size = Vector2(32, 30)
		IconAnim.attach(b, t[1])
		var what: String = t[0]
		b.pressed.connect(func(): action.emit(what))
		tools.add_child(b)
	add_child(tools)
	search = LineEdit.new()
	search.name = "MaterialSearch"
	search.placeholder_text = "Find a material..."
	search.add_theme_font_size_override("font_size", 14)
	search.clear_button_enabled = true
	search.tooltip_text = EditorIcons.tip("Find a material", "", "Narrows the materials to those whose name, group, kind or characters have these words.")
	search.text_changed.connect(func(_t): refill())
	add_child(search)
	_cats = HFlowContainer.new()
	_cats.add_theme_constant_override("h_separation", 4)
	_cats.add_theme_constant_override("v_separation", 4)
	add_child(_cats)
	for g in [""] + MaterialLibrary.GROUPS:
		var b := Button.new()
		b.text = "All" if g == "" else str(MaterialLibrary.GROUP_LABEL[g])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.name = "Group_" + (g if g != "" else "all")
		b.tooltip_text = EditorIcons.tip("Material group: " + b.text, "", {"": "Every material.", "model": "The open model's own materials.",
			"character": "Every character's named materials (from its model.json) - each says who wears it.",
			"preset": "The game's looks: bronze, gold, steel, painted armour, cloth, stone, glows...", "mine": "Your own materials (data/materials.json, or your mod's)."}[g])
		b.button_pressed = g == group
		b.pressed.connect(set_group.bind(g))
		_cat_btns[g] = b
		_cats.add_child(b)
	list = ItemList.new()
	list.name = "MaterialList"
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
	TurntableHover.attach(list, func(meta) -> Array: return thumbs.frames(str(_keys.get(str(meta), ""))) if thumbs else [])


func set_group(g: String) -> void:
	group = g
	for k in _cat_btns:
		(_cat_btns[k] as Button).set_pressed_no_signal(k == g)
	refill()


## The grid again (the library, the group or the search changed).
func refill() -> void:
	if lib == null or list == null:
		return
	var keep := selected()
	thumbs.clear_queue()
	list.clear()
	for id in lib.ids(group, search.text if search else ""):
		var i := list.add_item(str(lib.entry(id)["name"]), EditorIcons.get_icon("m_materials"))
		list.set_item_metadata(i, id)
		_dress(i, id)
		if id == keep:
			list.select(i)


## Item `i` (material `id`): its picture (asked for if it isn't made), tooltip and colour.
func _dress(i: int, id: String) -> void:
	var e := lib.entry(id)
	list.set_item_text(i, str(e["name"]))
	var k := lib.key_of(id)
	_keys[id] = k
	var tex: Texture2D = thumbs.get_thumb(k)
	if tex == null and not thumbs._reading.has(k):   # (not on its way from disk: drawn)
		var mat: Material = e["mat"] if e["group"] == "model" else lib.make_material(id)
		var arrays := MaterialLibrary.sphere_arrays()
		thumbs.ask_mesh(k, func(): return MaterialLibrary.sphere_mesh(arrays, mat))
	if tex:
		list.set_item_icon(i, tex)
	var kind := "a character's material (colour, metal, roughness, glow)" if e["kind"] == "character" else "a full material"
	var users: Array = e.get("users", [])
	var who := ("\nWorn by: " + ", ".join(users)) if not users.is_empty() else ""
	var slot := MaterialLibrary.slot_of(str(e["name"]))
	var ro := "" if lib.is_editable(id) else "  ·  built in (Duplicate it to change it)"
	list.set_item_tooltip(i, "%s\n%s  ·  %s%s%s%s\nClick: edit it (the MATERIAL panel) · double-click: give it to the selected surface or faces · drag it onto a surface in the view" % [
		e["name"], MaterialLibrary.GROUP_LABEL[e["group"]], kind, ("  ·  recolourable (%s)" % slot) if slot != "" else "", ro, who])
	if e["group"] == "mine":
		list.set_item_custom_fg_color(i, Color(0.55, 1.0, 0.6))
	elif e["group"] == "model":
		list.set_item_custom_fg_color(i, Color(1.0, 0.85, 0.55))


## Material `id`'s item again (its settings changed: a new picture).
func update_item(id: String) -> void:
	if list == null:
		return
	for i in list.item_count:
		if str(list.get_item_metadata(i)) == id:
			_dress(i, id)
			return


func selected() -> String:
	if list == null:
		return ""
	var s := list.get_selected_items()
	return str(list.get_item_metadata(s[0])) if not s.is_empty() else ""


func select_id(id: String) -> void:
	if list == null:
		return
	list.deselect_all()
	for i in list.item_count:
		if str(list.get_item_metadata(i)) == id:
			list.select(i)
			list.ensure_current_is_visible()
			return


func _made(key: String, tex: Texture2D) -> void:
	if list == null or not key.begins_with("mat|"):
		return
	for i in list.item_count:
		if str(_keys.get(str(list.get_item_metadata(i)), "")) == key:
			list.set_item_icon(i, tex)


## Dragging a material out of the grid (onto a surface in the 3D view): {"mesh_material": id}.
func _drag(at: Vector2) -> Variant:
	var i := list.get_item_at_position(at, true)
	if i < 0:
		return null
	var pv := TextureRect.new()
	pv.texture = list.get_item_icon(i)
	pv.custom_minimum_size = Vector2(56, 56)
	pv.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pv.modulate.a = 0.85
	set_drag_preview(pv)
	return {"mesh_material": str(list.get_item_metadata(i))}
