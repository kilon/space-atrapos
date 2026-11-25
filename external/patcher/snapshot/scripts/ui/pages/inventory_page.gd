extends HBoxContainer
## Automaton tab: your INVENTORY (everything you own: Inventory's stacks, up to
## 100 of an item a slot - drag them to arrange it), your TOOLBAR (the
## automaton's 9 slots: drag anything usable onto a slot - gear equipped or
## not, the automaton's tools, supplies - or hover it and press 1-9; drag a
## slot off the bar, or right-click it, to empty it) and the automaton's
## equipment (LoadoutPanel). Click gear in the inventory to equip it.

var data: Node
var ship: Node2D

var _grid: GridContainer
var _loadout: LoadoutPanel
var _details: Label
var _bar_foot: HBoxContainer
var _tools: HBoxContainer
var _inv_label: Label
var _hovered := ""


func _ready() -> void:
	add_theme_constant_override("separation", 30)
	# Two columns: your inventory, toolbar, tools and the hovered item's details | the automaton's equipment, filling the rest.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	add_child(left)
	left.add_child(UI.section("INVENTORY"))
	_inv_label = UI.note("", 13, 640)
	left.add_child(_inv_label)
	_grid = GridContainer.new()
	_grid.columns = 12
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	left.add_child(_grid)
	left.add_child(UI.section("TOOLBAR"))
	_bar_foot = HBoxContainer.new()
	_bar_foot.add_theme_constant_override("separation", 4)
	left.add_child(_bar_foot)
	_tools = HBoxContainer.new()
	_tools.add_theme_constant_override("separation", 4)
	left.add_child(_tools)
	_details = UI.label("", 14, UI.TEXT_DIM)   # (the hovered item's details, under your things)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(620, 80)
	left.add_child(_details)

	# The automaton: all the rest of the page - as large as it'll go, its slots spread round it.
	_loadout = LoadoutPanel.new()
	_loadout.fill = true
	_loadout.doll_height = 560.0
	_loadout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_loadout.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_loadout)


func refresh() -> void:
	# The automaton's equipment, from your inventory.
	_loadout.setup(data.loadout, data.items, Shipyard.cargo_capacity(data), "hold", func(): data.changed.emit())
	# The toolbar, and the automaton's tools (always with it: onto the toolbar).
	_fill_bar(_bar_foot, data.toolbar_foot)
	UI.clear(_tools)
	var tl := UI.label("TOOLS", 13, UI.TEXT_DIM)
	tl.custom_minimum_size.x = 70.0
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tools.add_child(tl)
	for tid in Inventory.TOOLS:
		var tool := ItemSlot.make(tid, 0, 42.0)
		tool.payload = {"src": "tool", "id": tid}
		tool.tooltip_text = "%s\n%s" % [Inventory.TOOLS[tid]["name"], Inventory.TOOLS[tid]["desc"]]
		tool.hovered.connect(func(_i): _hovered = tid)
		tool.mouse_exited.connect(func(): _hovered = "")
		_tools.add_child(tool)
	# The inventory: its slots, stacks of up to 100.
	UI.clear(_grid)
	var cap := Shipyard.cargo_capacity(data)
	var inv := Inventory.slots(data.items, data.layout_hold, cap)
	_inv_label.text = "%d / %d slots, up to %d of an item in each  ·  worth %d dr  ·  %d dr in hand" % [
		Inventory.slots_used(data.items), cap, Inventory.STACK, _value(), data.credits]
	for i in cap:
		var st: Array = inv[i]
		var slot := ItemSlot.make(st[0] if not st.is_empty() else "", int(st[1]) if not st.is_empty() else 0, 48.0)
		if not st.is_empty():
			slot.tooltip_text = Items.tooltip(st[0], int(st[1]), _hint(st[0]))
			slot.hovered.connect(_show_details)
			slot.mouse_exited.connect(func(): _hovered = "")
			slot.clicked.connect(_on_item_clicked)
			slot.payload = {"src": "hold", "index": i, "id": st[0]}
		slot.accepts = func(d): return d.get("src") == "hold" or _loadout.is_mine(d)
		slot.on_drop = _drop_on_slot.bind(i)
		_grid.add_child(slot)


## What clicking a stack does.
func _hint(id: String) -> String:
	if Gear.side(id) == "foot":
		return "Click (or drag it onto the automaton) to equip it."
	if Inventory.toolbar_id(id, true) != "":
		return "Drag it onto the toolbar, or hover it and press 1-9."
	return "Drag it to arrange your inventory."


func _show_details(id: String) -> void:
	_hovered = id
	var it: Dictionary = Items.info(id)
	var price := "Main quest item - cannot be sold." if it["kind"] == "quest" else "Sells for %d drachmas each." % it["value"]
	_details.text = "%s  ×%d\n%s\n%s" % [it["name"], data.count(id), it["desc"], price]


func _on_item_clicked(id: String) -> void:
	if Gear.side(id) == "foot":
		if _loadout.take_from_grid(id):
			GameLog.post("Equipped %s" % Gear.title(id), "good")
		refresh()


## The toolbar's row: its 9 slots, each showing how many you have; drops
## (Inventory.toolbar_drop), swaps, dragged off - emptied.
func _fill_bar(row: HBoxContainer, bar: Array) -> void:
	UI.clear(row)
	for i in bar.size():
		var tid: String = bar[i]
		var n := Inventory.toolbar_count(data, tid, true) if tid != "" else 0
		var ts := ItemSlot.make(tid, maxi(n, 0), 48.0, n == 0)
		ts.tooltip_text = "%d  %s" % [i + 1, Items.display_name(tid) if tid != "" else "-"]
		ts.gui_input.connect(_bar_input.bind(bar, i))
		ts.payload = {"src": "toolbar", "which": "foot", "index": i, "id": tid}
		ts.accepts = func(d): return Inventory.toolbar_accepts(d, true)
		ts.on_drop = func(d): Inventory.toolbar_drop(bar, i, d, true); refresh()
		ts.on_drag_lost = func(): Inventory.toolbar_clear(bar, i); refresh.call_deferred()
		row.add_child(ts)


func _bar_input(event: InputEvent, bar: Array, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		Inventory.toolbar_clear(bar, i)
		refresh()


## A stack dropped on an inventory slot: from the inventory - they swap; gear dragged off the automaton - taken off.
func _drop_on_slot(d: Dictionary, i: int) -> void:
	if _loadout.is_mine(d):
		_loadout.take_off(str(d["slot"]))
	elif d.get("src") == "hold":
		Inventory.swap(data.layout_hold, int(d["index"]), i)
	refresh()


## 1-9 over something usable: it goes on that slot of the toolbar.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _hovered == "" or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode < KEY_1 or event.keycode > KEY_9:
		return
	if Inventory.toolbar_id(_hovered, true) != "":
		Inventory.toolbar_drop(data.toolbar_foot, event.keycode - KEY_1, {"src": "hotkey", "id": _hovered}, true)
		get_viewport().set_input_as_handled()
		refresh()


func _value() -> int:
	var total := 0
	for id in data.held_items():
		total += Items.info(id)["value"] * data.count(id)
	return total
