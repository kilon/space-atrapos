extends HBoxContainer
## Field Computer tab: you on foot - health, your rifle, your toolbar (9 slots
## you fill: hover your rifle, medicine or an energy cell and press 1-9; right-
## click a toolbar slot to empty it) - and what you carry (Inventory:
## PLAYER_SLOTS slots, up to 100 of an item each; take things to and from
## your ship at the ship). Click medicine or an energy cell to use it. Three
## columns: you (stats, rifle, toolbar), the automaton's equipment
## (LoadoutPanel), what you carry.

var surface: Node

var _stats: Label
var _rifle: ItemSlot
var _bar: HBoxContainer
var _grid: GridContainer
var _carried_label: Label
var _details: Label
var _hovered := ""
var _loadout: LoadoutPanel
var _sig := 0                # what the slots were last built from


func _ready() -> void:
	add_theme_constant_override("separation", 32)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(420, 0)
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	left.add_child(UI.section("PILOT"))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var pic := TextureRect.new()
	pic.texture = SheetPuppet.portrait("player")
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(100, 160)
	row.add_child(pic)
	_stats = UI.label("", 16, UI.TEXT_DIM)
	row.add_child(_stats)
	left.add_child(row)
	left.add_child(UI.section("WEAPON"))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 12)
	_rifle = ItemSlot.make("laser", 0, 56.0)
	_rifle.payload = {"src": "gear", "id": "rifle"}   # (drag it onto the toolbar)
	_rifle.hovered.connect(func(_id): _hover("rifle"))
	_rifle.mouse_exited.connect(func(): _hovered = "")
	wrow.add_child(_rifle)
	wrow.add_child(UI.label("Laser rifle\nHover it and press 1-9 to put it on your toolbar.", 14, UI.TEXT_DIM))
	left.add_child(wrow)
	left.add_child(UI.section("TOOLBAR  ·  9 SLOTS"))
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 4)
	left.add_child(_bar)
	left.add_child(UI.note("Drag your rifle, medicine, an energy cell, food or an energy drink onto a slot (or hover it and press 1-9); drag slots to swap them; right-click a slot to empty it.", 13, 420))
	# The automaton's equipment: a column of its own, beside you and what you carry.
	_loadout = LoadoutPanel.new()
	_loadout.doll_height = 560.0   # (a column to itself: the automaton drawn large)
	add_child(_loadout)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	add_child(right)
	right.add_child(UI.section("YOU CARRY"))
	_carried_label = UI.note("", 14, 320)
	right.add_child(_carried_label)
	_grid = GridContainer.new()
	_grid.columns = 4
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	right.add_child(_grid)
	_details = UI.label("Hover an item for details.", 15, UI.TEXT_DIM)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(360, 80)
	right.add_child(_details)


func _carried() -> Dictionary:
	return surface.carried() if surface else {}


func refresh() -> void:
	if surface == null:
		return
	var pilot: Node = surface.pilot
	var player: Dictionary = surface.state["player"]
	var over: float = surface.overcharge_left()
	_stats.text = "Health      %d / %d\nStamina     %d / %d%s\nWeapon      %s%s\nDamage      %.0f %s\nRange       %.0f\nRate        %.1f shots/s\nCredits     %d" % [
		ceilf(pilot.hp), ceilf(pilot.max_hp), ceilf(pilot.stamina), Stamina.MAX, "  (tired)" if pilot.tired() else "", Gear.title(str(Gear.loadout(player).get("weapon", ""))), ("  (overcharged %ds)" % ceili(over)) if over > 0.0 else "",
		pilot.damage, pilot.damage_type, pilot.reach, 1.0 / pilot.fire_every(), int(player.get("credits", 0))]
	# The slots: rebuilt only when what's in them changed (the Field Computer
	# refreshes twice a second while open - rebuilding every slot each time
	# was a hitch every half second).
	var sig := str([surface.foot_toolbar(), _carried(), Inventory.layout(player, "carried"), Gear.loadout(player)]).hash()
	if sig == _sig and _grid.get_child_count() > 0:
		return
	_sig = sig
	# The loadout (Gear), from what you carry: your stats follow it at once.
	_loadout.setup(Gear.loadout(player), _carried(), Inventory.PLAYER_SLOTS, "carried", func(): surface.refresh_gear(); refresh())
	# The toolbar.
	UI.clear(_bar)
	var bar: Array = surface.foot_toolbar()
	for i in bar.size():
		var id: String = bar[i]
		var s := ItemSlot.make(SurfaceToolbar.ICONS.get(id, id) if id != "" else "", 0, 42.0)
		s.tooltip_text = "%d  %s\nDrag to another slot; right-click: empty it." % [i + 1, SurfaceToolbar.NAMES.get(id, "empty")]
		s.gui_input.connect(_bar_input.bind(i))
		s.payload = {"src": "toolbar", "which": "foot", "index": i, "id": id}
		s.accepts = func(d): return Inventory.toolbar_accepts(d, true)
		s.on_drop = func(d): Inventory.toolbar_drop(surface.foot_toolbar(), i, d, true); refresh()
		_bar.add_child(s)
	# What you carry.
	UI.clear(_grid)
	var inv := _carried()
	var lay := Inventory.layout(surface.state["player"], "carried")
	var stacks := Inventory.slots(inv, lay, Inventory.PLAYER_SLOTS)
	_carried_label.text = "%d / %d slots (up to %d of an item in each) - take things to and from your ship at the ship." % [
		Inventory.slots_used(inv), Inventory.PLAYER_SLOTS, Inventory.STACK]
	for i in Inventory.PLAYER_SLOTS:
		var st: Array = stacks[i]
		var slot := ItemSlot.make(st[0] if not st.is_empty() else "", int(st[1]) if not st.is_empty() else 0)
		if not st.is_empty():
			slot.tooltip_text = Items.tooltip(st[0], int(st[1]),
				"Click to use it; press 1-9 to put it on that toolbar slot." if Inventory.foot_usable(st[0])
				else ("Click (or drag it onto the automaton) to equip it." if Gear.side(st[0]) == "foot" else "Drag it to arrange what you carry."))
			slot.hovered.connect(_hover)
			slot.mouse_exited.connect(func(): _hovered = "")
			slot.clicked.connect(_on_item_clicked)
			slot.payload = {"src": "carried", "index": i, "id": st[0]}   # (to another slot, or onto the toolbar)
		slot.accepts = func(d): return d.get("src") == "carried" or _loadout.is_mine(d)
		slot.on_drop = func(d):
			if _loadout.is_mine(d):
				_loadout.take_off(str(d["slot"]))   # (gear dragged off the automaton)
			else:
				Inventory.swap(lay, int(d["index"]), i)
			refresh()
		_grid.add_child(slot)


func _bar_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		surface.foot_toolbar()[i] = ""
		refresh()


func _hover(id: String) -> void:
	_hovered = id
	if id == "rifle":
		_details.text = "Laser rifle\nYour weapon on foot: fire at the nearest enemy (or F).\nPress 1-9 to put it on that toolbar slot."
		return
	var it: Dictionary = Items.info(id)
	var use := ""
	if Inventory.foot_usable(id):
		use = "\nClick to use it; press 1-9 to put it on that toolbar slot."
	var price := "Main quest item - cannot be sold." if it["kind"] == "quest" else "Sells for %d drachmas each." % it["value"]
	_details.text = "%s  ×%d\n%s\n%s%s" % [it["name"], int(_carried().get(id, 0)), it["desc"], price, use]


## 1-9 over something usable: it goes on that toolbar slot.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _hovered == "" or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode < KEY_1 or event.keycode > KEY_9 or not Inventory.foot_usable(_hovered):
		return
	var bar: Array = surface.foot_toolbar()
	var i: int = event.keycode - KEY_1
	var was := bar.find(_hovered)
	if was >= 0:
		bar[was] = ""   # (one slot per tool: it moves)
	bar[i] = _hovered
	get_viewport().set_input_as_handled()
	refresh()


func _on_item_clicked(id: String) -> void:
	if Gear.side(id) == "foot":
		if _loadout.take_from_grid(id):
			GameLog.post("Equipped %s" % Gear.title(id), "good")
		return
	if id in ["medicine", "energy_cell"] or Stamina.restores(id) > 0.0:
		surface.use_item(id)
		refresh()
