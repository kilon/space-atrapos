extends HBoxContainer
## Ship Computer tab: ship status, weapons, systems, the toolbar (9 slots you
## fill: hover a weapon, a system or repair kits and press 1-9; right-click a
## toolbar slot to empty it), the cargo hold (its class's slots, up to 100 of
## an item each - Inventory) and what you carry on foot (click a stack to put
## it in the hold). Click a repair kit to use it, fuel to pump a unit into the tank.

var data: Node
var ship: Node2D

var _stats: Label
var _weapons: VBoxContainer
var _systems: VBoxContainer
var _grid: GridContainer
var _doll_holder: VBoxContainer
var _loadout: LoadoutPanel
var _details: Label
var _bar: HBoxContainer
var _hold_label: Label
var _carried: GridContainer
var _hovered := ""


func _ready() -> void:
	add_theme_constant_override("separation", 30)
	# Three columns, nothing to scroll: the ship (its equipment screen and
	# stats) | the hold, what you carry, the weapons and systems and the
	# toolbar | the automaton (its equipment screen) and the hovered item's details.
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(470, 0)
	left.add_theme_constant_override("separation", 8)
	add_child(left)

	# The ship's equipment screen (EquipDoll): its areas' slots round it.
	left.add_child(UI.section("SHIP  ·  EQUIPMENT"))
	_doll_holder = VBoxContainer.new()
	left.add_child(_doll_holder)
	_stats = UI.note("", 14, 470)
	left.add_child(_stats)
	left.add_child(UI.note("Weapons on the hardpoints (a weapon fits one its size or bigger), sensors in the nose, armour in the hull, drives at the thrusters, racks and tanks in the bay: drag ship gear from the hold onto a free slot of its area (or click it); right-click a module to take it out.", 12, 470))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 8)
	add_child(mid)
	mid.add_child(UI.section("CARGO HOLD"))
	_hold_label = UI.note("", 13, 400)
	mid.add_child(_hold_label)
	_grid = GridContainer.new()
	_grid.columns = 12   # (up to 120 slots, a freighter's: 10 rows)
	_grid.add_theme_constant_override("h_separation", 4)
	_grid.add_theme_constant_override("v_separation", 4)
	mid.add_child(_grid)
	mid.add_child(UI.section("YOU CARRY ON FOOT"))
	_carried = GridContainer.new()
	_carried.columns = 12
	_carried.add_theme_constant_override("h_separation", 4)
	mid.add_child(_carried)
	# The weapons and the toolbar under the hold (the ship's column is full).
	mid.add_child(UI.section("WEAPONS & SYSTEMS"))
	_weapons = VBoxContainer.new()
	mid.add_child(_weapons)
	_systems = VBoxContainer.new()   # (kept for older code paths: the row above holds them all)
	mid.add_child(UI.section("TOOLBAR  ·  9 SLOTS"))
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 4)
	mid.add_child(_bar)
	mid.add_child(UI.note("Drag a weapon, a system or repair kits onto a slot (or hover it and press 1-9); drag slots to swap them; right-click a slot to empty it.", 12, 400))

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	add_child(right)
	_loadout = LoadoutPanel.new()
	_loadout.doll_height = 480.0
	right.add_child(_loadout)
	_details = UI.label("Hover an item for details.", 14, UI.TEXT_DIM)
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(440, 80)
	right.add_child(_details)


func refresh() -> void:
	_stats.text = "Hull %d / %d  ·  Shields %d / %d  ·  Fuel %d / %d  ·  Speed %d\nWeapons %d fitted  ·  firepower %.0f /s  ·  reach %.0f  ·  accuracy %d%%  ·  evasion %d%%\nDrachmas %d  ·  cargo worth %d dr" % [
		ceilf(ship.hull), ship.max_hull, ceilf(ship.shields), ship.max_shields, floori(data.fuel_level()), roundi(data.fuel_max()),
		ship.max_speed, Shipyard.used_slots(data, "hardpoints"), OutfitCompare.firepower(data),
		ship.weapon_range, roundi(ship.accuracy() * 100.0), roundi(ship.evasion * 100.0), data.credits, _cargo_value()]

	# Weapon kinds and systems: one row of icons (greyed: none fitted), each
	# draggable onto the toolbar (a kind's key switches it on / off); the kinds firing lit.
	UI.clear(_weapons)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_weapons.add_child(row)
	for id in Items.WEAPONS.keys() + ["afterburner", "shield_booster", "star_energizer", "cloak", "projection_array"]:
		var owned: bool = data.has_equipment(id)
		var name: String = Items.WEAPONS[id]["name"] if Items.WEAPONS.has(id) else Items.EQUIPMENT[id]["name"]
		var n := Hardpoints.fitted(data).filter(func(w): return w != "" and Hardpoints.kind(w) == id).size()
		var status := ("%d fitted  ·  %s" % [n, "firing" if ship.weapon_on(id) else "switched off"]) if Items.WEAPONS.has(id) and owned \
			else ("installed" if owned else "not installed - buy one at a station's Outfitting")
		if id == "missile_launcher" and owned:
			status += "  ·  %d missiles" % data.count("missile")
		var icon := ItemSlot.make(id, 0, 42.0, not owned)
		icon.payload = {"src": "gear", "id": id}   # (drag it onto the toolbar)
		icon.hovered.connect(func(_i): _hovered = id)
		icon.mouse_exited.connect(func(): _hovered = "")
		icon.tooltip_text = "%s  ·  %s\n%s\nDrag it onto the toolbar, or hover it and press 1-9." % [name, status, Items.EQUIPMENT[id]["desc"]]
		if Items.WEAPONS.has(id) and owned and ship.weapon_on(id):
			icon.modulate = Color(1.25, 1.15, 0.9)
		row.add_child(icon)

	# The ship's equipment screen: every area's fittings and free slots.
	UI.clear(_doll_holder)
	var sd := ship_doll(data, ship, _ship_gear_input, _fit)
	sd.custom_minimum_size.y = 440.0   # (the column has the room: the ship drawn larger)
	_doll_holder.add_child(sd)
	# The automaton's loadout, from the hold.
	_loadout.setup(data.loadout, data.items, Shipyard.cargo_capacity(data), "hold", func(): data.changed.emit())
	# The toolbar.
	UI.clear(_bar)
	for i in data.toolbar.size():
		var tid: String = data.toolbar[i]
		var ts := ItemSlot.make(tid, 0, 42.0)
		ts.tooltip_text = "%d  %s\nDrag to another slot; right-click: empty it." % [i + 1, Items.display_name(tid) if tid != "" else "empty"]
		ts.gui_input.connect(_bar_input.bind(i))
		ts.payload = {"src": "toolbar", "which": "ship", "index": i, "id": tid}
		ts.accepts = func(d): return Inventory.toolbar_accepts(d, false)
		ts.on_drop = func(d): Inventory.toolbar_drop(data.toolbar, i, d, false); refresh()
		_bar.add_child(ts)
	# The hold: its class's slots, stacks of up to 100.
	UI.clear(_grid)
	var cap := Shipyard.cargo_capacity(data)
	var hold := Inventory.slots(data.items, data.layout_hold, cap)
	_hold_label.text = "%d / %d slots, up to %d of an item in each - drag stacks to arrange them" % [Inventory.slots_used(data.items), cap, Inventory.STACK]
	for i in cap:
		var st: Array = hold[i]
		var slot := ItemSlot.make(st[0] if not st.is_empty() else "", int(st[1]) if not st.is_empty() else 0, 48.0)
		if not st.is_empty():
			slot.tooltip_text = Items.tooltip(st[0], int(st[1]), _hold_hint(st[0]))
			slot.hovered.connect(_show_details)
			slot.mouse_exited.connect(func(): _hovered = "")
			slot.clicked.connect(_on_item_clicked)
			slot.payload = {"src": "hold", "index": i, "id": st[0]}
		slot.accepts = func(d): return d.get("src") in ["hold", "carried"] or _loadout.is_mine(d)
		slot.on_drop = _drop_on_hold.bind(i)
		_grid.add_child(slot)
	# What you carry on foot (aboard: click a stack to stow it in the hold).
	UI.clear(_carried)
	var mine := Inventory.slots(data.carried, data.layout_carried, Inventory.PLAYER_SLOTS)
	for i in Inventory.PLAYER_SLOTS:
		var st: Array = mine[i]
		var cs := ItemSlot.make(st[0] if not st.is_empty() else "", int(st[1]) if not st.is_empty() else 0, 40.0)
		if not st.is_empty():
			cs.tooltip_text = Items.tooltip(st[0], int(st[1]), "Click (or drag it into the hold) to stow it.")
			cs.clicked.connect(_stow)
			cs.payload = {"src": "carried", "index": i, "id": st[0]}
		cs.accepts = func(d): return d.get("src") in ["hold", "carried"]
		cs.on_drop = _drop_on_carried.bind(i)
		_carried.add_child(cs)


func _row(id: String, title: String, status: String, dim: bool, highlight: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := ItemSlot.make(id, 0, 40.0, dim)
	icon.payload = {"src": "gear", "id": id}   # (drag it onto the toolbar)
	icon.hovered.connect(func(_i): _hovered = id)
	icon.mouse_exited.connect(func(): _hovered = "")
	icon.tooltip_text = "%s\nPress 1-9 to put it on that toolbar slot." % title
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.add_child(UI.label(title, 16, Color.WHITE if not dim else Color(0.6, 0.6, 0.65)))
	text.add_child(UI.label(status, 13, NeonTheme.HEAD if highlight else UI.TEXT_DIM))
	row.add_child(text)
	return row


## What clicking a stack in the hold does.
func _hold_hint(id: String) -> String:
	if Gear.side(id) == "ship":
		return "Click (or drag it onto a free slot of its area) to fit it."
	if Gear.side(id) == "foot":
		return "Click (or drag it onto the automaton) to equip it."
	if id == "repair_kit":
		return "Click to use it (+40 hull); press 1-9 to put it on that toolbar slot."
	if id == "fuel":
		return "Click to pump a unit into the tank (+%d fuel)." % Shipyard.FUEL_UNITS_PER_CARGO
	return "Drag it to arrange the hold."


func _show_details(id: String) -> void:
	_hovered = id
	var it: Dictionary = Items.info(id)
	var price := "Main quest item - cannot be sold." if it["kind"] == "quest" else "Sells for %d drachmas each." % it["value"]
	_details.text = "%s  ×%d\n%s\n%s" % [it["name"], data.count(id), it["desc"], price]


## Where each ship area's slots sit round the ship (pointing up) and the spot
## on it they belong to: [at (0..1 of the doll), anchor (0..1 of the ship), vertical].
const SHIP_PLACES := {
	"nose": [Vector2(0.5, 0.0), Vector2(0.5, 0.06), false],
	"wings": [Vector2(0.0, 0.5), Vector2(0.16, 0.62), true],
	"hull": [Vector2(1.0, 0.18), Vector2(0.5, 0.42), true],
	"bay": [Vector2(1.0, 0.8), Vector2(0.5, 0.66), true],
	"thrusters": [Vector2(0.5, 1.0), Vector2(0.5, 0.95), false],
}


## The ship's equipment screen (EquipDoll): `on_module(event, index)` for
## a fitted module's slot input, `on_fit(item_id)` for gear dropped on a
## free slot.
static func ship_doll(data: Node, ship: Node2D, on_module: Callable, on_fit: Callable) -> EquipDoll:
	var d := EquipDoll.new()
	var tex: Texture2D = ship.sprite.texture if ship and ship.get("sprite") and ship.sprite is Sprite2D else ProcArt.get_tex("ship_player")
	d.picture = tex
	for area in Shipyard.AREAS:
		var slots := []
		var name: String = Shipyard.AREA_NAMES[area]
		if area == "wings":
			slots = _hardpoint_slots(data, on_fit)
			var place0: Array = SHIP_PLACES[area]
			d.add_group(area, "%s  %d/%d" % ["HARDPOINTS", Shipyard.used_slots(data, "hardpoints"), slots.size()], place0[0], place0[1], place0[2], slots)
			continue
		for f in Shipyard.area_fittings(data, area):
			if f["kind"] == "module":
				var gid := Gear.item_id(f["id"], int(f["rating"]))
				var gs := ItemSlot.make(gid, 0, 44.0)
				gs.tooltip_text = "%s  ·  %s\n%s\nRight-click: take it out into the hold." % [name, Gear.title(gid), Gear.describe(gid)]
				gs.gui_input.connect(on_module.bind(int(f["index"])))
				slots.append(gs)
			else:
				var es := ItemSlot.make(f["id"], 0, 44.0)
				es.payload = {"src": "gear", "id": f["id"]}   # (drag it onto the toolbar)
				es.tooltip_text = "%s  ·  %s\n%s\n(Sold back at a station's Outfitting.)" % [name, Items.EQUIPMENT[f["id"]]["name"], Items.EQUIPMENT[f["id"]]["desc"]]
				slots.append(es)
		for k in maxi(0, Shipyard.area_capacity(data, area) - slots.size()):
			var free := ItemSlot.make("", 0, 44.0)
			free.tooltip_text = "%s  ·  free\nDrag ship gear for the %s here from the hold." % [name, name.to_lower()]
			free.accepts = func(dd): return dd.get("src") == "hold" and Gear.side(str(dd.get("id", ""))) == "ship" and Shipyard.area_of(str(dd["id"])) == area
			free.on_drop = func(dd): on_fit.call(str(dd["id"]))
			slots.append(free)
		var place: Array = SHIP_PLACES[area]
		d.add_group(area, "%s  %d/%d" % [name.to_upper(), mini(slots.size(), Shipyard.area_fittings(data, area).size()), Shipyard.area_capacity(data, area)],
			place[0], place[1], place[2], slots)
	return d


## A slot a hardpoint (Hardpoints): its weapon (drag it to the toolbar - its
## kind's switch; right-click: into the hold) or, free, a place to drop a
## weapon from the hold that fits its size. Smaller the more there are.
static func _hardpoint_slots(data: Node, on_fit: Callable) -> Array:
	var out := []
	var lay := Hardpoints.layout(data.ship_class)
	var ws := Hardpoints.fitted(data)
	var px := 44.0 if lay.size() <= 6 else (34.0 if lay.size() <= 12 else 28.0)
	for i in lay.size():
		var z: int = lay[i]
		var id: String = ws[i]
		var sl := ItemSlot.make(id, 0, px)
		if id != "":
			sl.payload = {"src": "gear", "id": Hardpoints.kind(id)}   # (onto the toolbar: its kind's switch)
			sl.tooltip_text = "Hardpoint %d (%s)  ·  %s\n%s\nRight-click: take it out into the hold. Drag it to the toolbar: a key to switch its kind on and off." % [
				i + 1, Hardpoints.SIZES[z], Hardpoints.title(id), Hardpoints.describe(id)]
			sl.gui_input.connect(func(ev: InputEvent):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
					if Hardpoints.unfit(data, i):
						GameLog.post("%s taken out into your hold" % Hardpoints.title(id), "info")
					else:
						GameLog.post("No room in the hold for it", "danger"))
		else:
			sl.tooltip_text = "Hardpoint %d (%s)  ·  free\nDrag a weapon of size %s or smaller here from the hold." % [i + 1, Hardpoints.SIZES[z], Hardpoints.SIZES[z]]
			sl.accepts = func(dd): return dd.get("src") == "hold" and Hardpoints.fits(str(dd.get("id", "")), z)
			sl.on_drop = func(dd):
				if Hardpoints.fit(data, str(dd["id"]), i):
					GameLog.post("Fitted %s" % Hardpoints.title(str(dd["id"])), "good")
		out.append(sl)
	return out


func _ship_gear_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		var m: Dictionary = data.modules[i]
		if Gear.unfit(data, i):
			GameLog.post("%s taken out into your hold" % Shipyard.module_name(m), "info")
			data.changed.emit()
		else:
			GameLog.post("No room in the hold for it", "danger")
		refresh()


func _fit(id: String) -> void:
	if Gear.fit(data, id):
		GameLog.post("Fitted %s" % Gear.title(id), "good")
		data.changed.emit()
	else:
		GameLog.post("No room in the %s for %s" % [Shipyard.AREA_NAMES[Shipyard.area_of(id)].to_lower(), Gear.title(id)], "danger")
	refresh()


func _on_item_clicked(id: String) -> void:
	if Hardpoints.is_weapon(id):   # (a weapon in the hold: onto a free hardpoint that takes it)
		if Hardpoints.fit(data, id):
			GameLog.post("Fitted %s" % Hardpoints.title(id), "good")
		else:
			GameLog.post("No free hardpoint of size %s or bigger for %s" % [Hardpoints.SIZES[Hardpoints.size_of(id)], Hardpoints.title(id)], "danger")
		refresh()
		return
	if Gear.side(id) == "ship":
		_fit(id)
		return
	if Gear.side(id) == "foot":
		if _loadout.take_from_grid(id):
			GameLog.post("Equipped %s" % Gear.title(id), "good")
		refresh()
		return
	if id == "repair_kit":
		ship.use_system("repair_kit")
	elif id == "fuel" and data.fuel_level() < data.fuel_max() - 0.5:
		# Fuel in the hold: a unit pumped into the tank (Shipyard.FUEL_UNITS_PER_CARGO).
		if data.remove_item("fuel", 1):
			data.add_fuel(Shipyard.FUEL_UNITS_PER_CARGO)
			GameLog.post("Pumped a unit of fuel into the tank (%d / %d)" % [floori(data.fuel_level()), roundi(data.fuel_max())], "info")
		refresh()


func _bar_input(event: InputEvent, i: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		data.toolbar[i] = ""
		refresh()


## A stack dropped on a hold slot: from the hold - they swap; from what you
## carry - it's stowed there.
func _drop_on_hold(d: Dictionary, i: int) -> void:
	if _loadout.is_mine(d):
		_loadout.take_off(str(d["slot"]))   # (gear dragged off the automaton)
	elif d.get("src") == "hold":
		Inventory.swap(data.layout_hold, int(d["index"]), i)
	else:
		Inventory.move_stack_into(data.carried, data.items, d["id"], Shipyard.cargo_capacity(data), data.layout_hold, i)
		data.changed.emit()
	refresh()


func _drop_on_carried(d: Dictionary, i: int) -> void:
	if d.get("src") == "carried":
		Inventory.swap(data.layout_carried, int(d["index"]), i)
	else:
		Inventory.move_stack_into(data.items, data.carried, d["id"], Inventory.PLAYER_SLOTS, data.layout_carried, i)
		data.changed.emit()
	refresh()


## Something you carry on foot into the hold (one stack).
func _stow(id: String) -> void:
	if Inventory.move_stack(data.carried, data.items, id, Shipyard.cargo_capacity(data)) > 0:
		data.changed.emit()
	else:
		GameLog.post("Cargo hold full (%d slots)" % Shipyard.cargo_capacity(data), "danger")
	refresh()


## 1-9 over a weapon, a system or repair kits: it goes on that toolbar slot.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _hovered == "" or not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode < KEY_1 or event.keycode > KEY_9 or not Inventory.ship_usable(_hovered):
		return
	var i: int = event.keycode - KEY_1
	var was: int = data.toolbar.find(_hovered)
	if was >= 0:
		data.toolbar[was] = ""   # (one slot per tool: it moves)
	data.toolbar[i] = _hovered
	get_viewport().set_input_as_handled()
	refresh()


func _cargo_value() -> int:
	var total := 0
	for id in data.held_items():
		total += Items.info(id)["value"] * data.count(id)
	return total
