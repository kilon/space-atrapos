class_name TransferPanel
extends CanvasLayer
## At your ship on a planet (clicking it: PlanetSurface.board_ship): what you
## carry (Inventory.PLAYER_SLOTS slots) beside the ship's hold (its class's
## slots, Shipyard.cargo_capacity) - click a stack on either side to move it
## to the other (up to 100 at a time, as far as there's room). Take off, or
## close and stay. The game waits while it's open.

const COLS_YOU := 4
const COLS_SHIP := 10
const SLOT := 56.0

var surface: Node
var _you: GridContainer
var _ship: GridContainer
var _you_label: Label
var _ship_label: Label
var _status: Label
var _was_paused := false


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_was_paused = get_tree().paused
	get_tree().paused = true
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var v := UI.modal(root, NeonTheme.CYAN, Vector2(980, 0))
	var head := HBoxContainer.new()
	head.add_child(UI.label("YOUR SHIP", 24, NeonTheme.CYAN))
	head.add_child(UI.spacer())
	head.add_child(UI.label("Click a stack to move it across (up to 100 at a time).", 14, UI.TEXT_DIM))
	v.add_child(head)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	v.add_child(cols)
	var left := VBoxContainer.new()
	_you_label = UI.label("", 16, UI.GOLD)
	left.add_child(_you_label)
	_you = _grid(COLS_YOU)
	left.add_child(_you)
	cols.add_child(left)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ship_label = UI.label("", 16, UI.GOLD)
	right.add_child(_ship_label)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(COLS_SHIP * (SLOT + 6), 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_ship = _grid(COLS_SHIP)
	scroll.add_child(_ship)
	right.add_child(scroll)
	cols.add_child(right)
	_status = UI.label("", 14, UI.TEXT_DIM)
	v.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_child(UI.spacer())
	buttons.add_child(UI.button("Stay", close, 16))
	buttons.add_child(UI.button("Take off", _take_off, 16))
	v.add_child(buttons)
	refresh()


func _grid(cols: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	return g


func _player() -> Dictionary:
	return surface.state["player"]


## The ship's hold size in slots (its class, its Cargo Racks).
func ship_slots() -> int:
	var pd: Node = preload("res://scripts/sim/player_data.gd").new()
	pd.load_save_data(_player())
	var n := Shipyard.cargo_capacity(pd)
	pd.free()
	return n


func refresh() -> void:
	var you: Dictionary = Inventory.carried(_player())
	var hold: Dictionary = _player().get("items", {})
	var cap := ship_slots()
	_you_label.text = "YOU CARRY  ·  %d / %d slots" % [Inventory.slots_used(you), Inventory.PLAYER_SLOTS]
	_ship_label.text = "SHIP'S HOLD  ·  %d / %d slots" % [Inventory.slots_used(hold), cap]
	_fill(_you, Inventory.slots(you, Inventory.layout(_player(), "carried"), Inventory.PLAYER_SLOTS), "carried", _to_ship)
	_fill(_ship, Inventory.slots(hold, Inventory.layout(_player(), "hold"), cap), "hold", _to_you)


## A grid of slots: click a stack to move it across; drag it to another slot
## (they swap) or into the other grid (it moves there, into that slot).
func _fill(g: GridContainer, slots_: Array, which: String, on_click: Callable) -> void:
	UI.clear(g)
	for i in slots_.size():
		var st: Array = slots_[i]
		var s := ItemSlot.make(st[0] if not st.is_empty() else "", int(st[1]) if not st.is_empty() else 0, SLOT)
		if not st.is_empty():
			s.clicked.connect(on_click)
			s.tooltip_text = "%s  ×%d\nClick or drag it across; drag it to another slot to arrange." % [Items.display_name(st[0]), int(st[1])]
			s.payload = {"src": which, "index": i, "id": st[0]}
		s.accepts = func(d): return d.get("src") in ["hold", "carried"]
		s.on_drop = _dropped.bind(which, i)
		g.add_child(s)


func _dropped(d: Dictionary, which: String, i: int) -> void:
	var pl := _player()
	if d.get("src") == which:
		Inventory.swap(Inventory.layout(pl, which), int(d["index"]), i)
		refresh()
		return
	var n: int
	if which == "hold":
		n = Inventory.move_stack_into(Inventory.carried(pl), pl["items"], d["id"], ship_slots(), Inventory.layout(pl, "hold"), i)
	else:
		n = Inventory.move_stack_into(pl["items"], Inventory.carried(pl), d["id"], Inventory.PLAYER_SLOTS, Inventory.layout(pl, "carried"), i)
	_status.text = ("%d %s moved." % [n, Items.display_name(d["id"])]) if n > 0 else "No room there."
	_moved()


func _to_ship(id: String) -> void:
	var n := Inventory.move_stack(Inventory.carried(_player()), _player()["items"], id, ship_slots())
	_status.text = ("%d %s into the ship's hold." % [n, Items.display_name(id)]) if n > 0 else "The ship's hold is full."
	_moved()


func _to_you(id: String) -> void:
	var n := Inventory.move_stack(_player()["items"], Inventory.carried(_player()), id, Inventory.PLAYER_SLOTS)
	_status.text = ("You take %d %s." % [n, Items.display_name(id)]) if n > 0 else "You can't carry any more (%d slots)." % Inventory.PLAYER_SLOTS
	_moved()


func _moved() -> void:
	Sfx.play("pirate/loot_take", -6.0)
	refresh()
	surface._update_hud()


func close() -> void:
	get_tree().paused = _was_paused
	queue_free()


func _take_off() -> void:
	close()
	surface.confirm_leave()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
