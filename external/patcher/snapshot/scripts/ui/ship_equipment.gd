class_name ShipEquipment
## The ship's equipment screen (EquipDoll): its areas' slots round the ship -
## hardpoints, nose, hull, bay, thrusters - fitted modules and free slots.
## (It was the Automaton's inventory page's; the ship's equipment is the
## ship's own now - kept here for a ship-side screen to show.)

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
