class_name RegainPopup
extends CanvasLayer
## "ITEM REGAINED" and the item's name, in the upper middle of the screen for
## a few seconds (LostItems: a lost item won back by a kill) - fades in, holds
## HOLD s, fades out and goes. RegainPopup.show_item(tree, name).

const HOLD := 3.0
var item_name := ""
var _box: PanelContainer


static func show_item(tree: SceneTree, name: String) -> RegainPopup:
	for old in tree.root.get_children():   # (one at a time: a newer one replaces it)
		if old is RegainPopup:
			old.queue_free()
	var p := RegainPopup.new()
	p.item_name = name
	tree.root.add_child(p)
	return p


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(NeonTheme.BG, 0.88)
	sb.border_color = Color(0.4, 1.0, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	_box.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 4)
	var head := UI.label("ITEM REGAINED", 26, Color(0.45, 1.0, 0.6))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var nm := UI.label(item_name + "  recovered", 20, Color(1.0, 0.92, 0.7))
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	col.add_child(nm)
	_box.add_child(col)
	# Centred in a band across the screen, 18 % down.
	var band := CenterContainer.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.18
	band.anchor_bottom = 0.18
	band.offset_bottom = 110.0
	root.add_child(band)
	band.add_child(_box)
	_box.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(_box, "modulate:a", 1.0, 0.25)
	tw.tween_interval(HOLD)
	tw.tween_property(_box, "modulate:a", 0.0, 0.6)
	tw.tween_callback(queue_free)
