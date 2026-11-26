extends VBoxContainer
## The ECurves editor's Primitives tab: the primitive solids of ECurve objects (CurveTools.CURVE_PRIMS) as
## icons - double-click one to add it to the open object, or drag it into the view (where it's dropped).

var ct: Node   # the curve tools
var list: ItemList


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	list = ItemList.new()
	list.name = "Primitives"
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.focus_mode = Control.FOCUS_NONE
	list.max_columns = 0
	list.icon_mode = ItemList.ICON_MODE_TOP
	list.fixed_column_width = 96
	list.fixed_icon_size = Vector2i(40, 40)
	list.add_theme_font_size_override("font_size", 14)
	list.tooltip_text = ""
	add_child(list)
	for d in ct.CURVE_PRIMS:
		var i := list.add_item(str(d[2]), EditorIcons.get_icon(str(d[1])))
		list.set_item_metadata(i, str(d[0]))
		list.set_item_tooltip(i, EditorIcons.tip(str(d[2]), "double-click / drag", str(d[3]) + "\nAn ECurve solid: reshape its edges and it follows."))
	list.item_activated.connect(func(i): ct.add_curve_primitive(str(list.get_item_metadata(i))))
	list.set_drag_forwarding(_drag, Callable(), Callable())


func _drag(at: Vector2) -> Variant:
	var i := list.get_item_at_position(at, true)
	if i < 0:
		return null
	var l := Label.new()
	l.text = list.get_item_text(i)
	list.set_drag_preview(l)
	return {"ecurve_prim": str(list.get_item_metadata(i))}
