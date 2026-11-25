class_name ChestMenu
extends Control
## A chest you built (CosmosBuilds): what's in it beside what you have (what
## you carry and your hold) - one or all of a kind moved across with a click.
## Its things are in its record (BuildKit: "inv"), in the save; BuildKit.CHEST_SLOTS
## stacks of them.

var chest := {}
var _mine: VBoxContainer
var _its: VBoxContainer
var _title: Label
var _root: VBoxContainer


func _ready() -> void:
	hide()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	Keybinds.register_menu(self)


func _build() -> void:
	_root = UI.modal(self, Color(NeonTheme.TEXT_DIM, 0.9), Vector2(980, 600))
	var header := HBoxContainer.new()
	_title = UI.label("CHEST", 28, NeonTheme.HEAD)
	header.add_child(_title)
	header.add_child(UI.spacer())
	header.add_child(EditorIcons.dress(UI.button("", close), "close", EditorIcons.tip("Close", "Esc", "Shuts the chest.")))
	_root.add_child(header)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	cols.size_flags_vertical = SIZE_EXPAND_FILL
	_root.add_child(cols)
	_mine = _column(cols, "YOURS - CARRIED AND IN THE HOLD")
	_its = _column(cols, "IN THE CHEST")


func _column(parent: Control, title: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_child(UI.section(title))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = SIZE_EXPAND_FILL
	sc.custom_minimum_size.y = 440
	v.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	sc.add_child(list)
	parent.add_child(v)
	return list


func open(pc: Dictionary) -> void:
	if _root == null:
		_build()
	chest = pc
	if not chest.has("inv"):
		chest["inv"] = {}
	var was_open := visible and not HexReveal.closing(self)
	show()
	refresh()
	if not was_open:
		HexReveal.play(self)


func close() -> void:
	if not visible:
		return
	HexReveal.play(self, true, hide)


func refresh() -> void:
	UI.clear(_mine)
	UI.clear(_its)
	var d: Node = CosmosGame.data
	var mine := {}
	for k in d.carried:
		mine[k] = int(mine.get(k, 0)) + int(d.carried[k])
	for k in d.items:
		mine[k] = int(mine.get(k, 0)) + int(d.items[k])
	var keys := mine.keys()
	keys.sort()
	for k in keys:
		if int(mine[k]) > 0 and Items.exists(k) and not Inventory.is_tool_id(k):
			_mine.add_child(_row(k, int(mine[k]), true))
	var inv: Dictionary = chest["inv"]
	var ck := inv.keys()
	ck.sort()
	for k in ck:
		if int(inv[k]) > 0:
			_its.add_child(_row(k, int(inv[k]), false))
	if ck.is_empty():
		_its.add_child(UI.label("Empty - up to %d stacks" % BuildKit.CHEST_SLOTS, 16, NeonTheme.TEXT_DIM))
	UI.scale_fonts(_root, "menu", 1.3)


func _row(id: String, n: int, mine: bool) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var ic := TextureRect.new()
	ic.texture = Items.icon_texture(id)
	ic.custom_minimum_size = Vector2(32, 32)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(ic)
	var l := UI.label("%s  x%d" % [Items.display_name(id), n], 16, NeonTheme.TEXT)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	h.add_child(l)
	for amount in [1, n]:
		var b := UI.light_button(UI.button(("Store " if mine else "Take ") + ("1" if amount == 1 and n > 1 else "all"), func(): move(id, amount, mine), 15))
		b.focus_mode = Control.FOCUS_NONE
		var what := ("one " + Items.display_name(id)) if amount == 1 and n > 1 else ("all %d %s" % [n, Items.display_name(id)] if n > 1 else "the " + Items.display_name(id))
		b.tooltip_text = ("Puts %s in the chest (from what you carry first, then your hold)." if mine else "Takes %s out of the chest, into your hold.") % what
		h.add_child(b)
		if n == 1:
			break
	return h


## Moves `n` of `id` into the chest (`store`) or out of it into your hold. How many went.
func move(id: String, n: int, store: bool) -> int:
	var d: Node = CosmosGame.data
	var inv: Dictionary = chest["inv"]
	for k in inv.keys():
		inv[k] = int(inv[k])
	var moved := 0
	if store:
		n = mini(n, Inventory.room_for(inv, id, BuildKit.CHEST_SLOTS))
		var from_c := Inventory.take(d.carried, id, n)
		moved = from_c
		if moved < n:
			var k := mini(n - moved, d.count(id))
			if k > 0 and d.remove_item(id, k):
				moved += k
		if moved > 0:
			inv[id] = int(inv.get(id, 0)) + moved
	else:
		n = mini(n, int(inv.get(id, 0)))
		if n > 0:
			Inventory.take(inv, id, n)
			d.add_item(id, n)
			moved = n
	d.changed.emit()
	refresh()
	return moved


func _input(event: InputEvent) -> void:
	if not visible or UI.esc_menu_open():
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
