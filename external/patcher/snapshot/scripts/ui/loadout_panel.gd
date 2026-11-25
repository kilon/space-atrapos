class_name LoadoutPanel
extends VBoxContainer
## The automaton's loadout (Gear.LOADOUT: weapon, two weapon mods, armour,
## core, two passives) as an equipment screen (EquipDoll): the automaton drawn
## large - its actual 3D model (ModelView: drag to turn it round) - each slot beside its area of the body (Gear.AREA_OF_SLOT: the rifle
## in the right arm, the core in the head...) - in the Automaton's
## inventory (gear from the hold) and the Field Computer's (gear you carry). Drag a piece of
## gear from the grid onto a slot that takes it (or click it in the grid:
## Gear.slot_for); click a slot (or right-click it, or drag it back onto the
## grid: the grid's drop calls take_off) to take it off into the grid. Below:
## what the loadout gives you.
##   var p := LoadoutPanel.new(); p.setup(loadout, inv, cap, src, on_change)

const SLOT := 52.0

var lo: Dictionary            # the loadout {slot: gear item id}
var inv: Dictionary           # where gear comes from / goes back to
var cap := 12                 # its slots
var src := "hold"             # the grid's drag source ("hold" / "carried")
var on_change := Callable()   # after a change (refresh the page, the stats)
## How tall the automaton's screen is (px; its picture grows with it) - a
## page with room makes it bigger.
var doll_height := 350.0
## Fill all the room it's given (the Automaton's Inventory: the automaton as large as
## the page allows, its slots spread round it) - else doll_height tall.
var fill := false
## The how-to line under the automaton.
const HINT := "Click gear in your items (or drag it onto the automaton) to equip it; click its slot (or drag it back to your items) to take it off."

var _doll: EquipDoll
var _stats: Label
## Where each slot's group sits round the automaton and the spot on it it
## belongs to: [at (0..1 of the doll), anchor (0..1 of the picture), vertical].
const PLACES := {
	"core": [Vector2(0.5, 0.0), Vector2(0.5, 0.12), false],
	"passive2": [Vector2(0.0, 0.06), Vector2(0.42, 0.3), true],
	"armour": [Vector2(1.0, 0.18), Vector2(0.52, 0.4), true],
	"weapon": [Vector2(0.0, 0.42), Vector2(0.26, 0.46), true],
	"mod1": [Vector2(0.0, 0.78), Vector2(0.22, 0.62), true],
	"mod2": [Vector2(1.0, 0.58), Vector2(0.74, 0.46), true],
	"passive1": [Vector2(0.5, 1.0), Vector2(0.5, 0.84), false],
}


## The automaton's picture (you on foot, facing the camera).
static func picture() -> Texture2D:
	var path := AssetCatalog.first_file(["res://art/player/player_idle_s.png", "res://art/player/player_aim_s.png",
		"res://art/player/player_walk_s_0.png"])
	return load(path) if path != "" else null


func setup(loadout: Dictionary, inventory: Dictionary, slots: int, source: String, changed: Callable) -> void:
	lo = loadout
	inv = inventory
	cap = slots
	src = source
	on_change = changed
	refresh()


func _ready() -> void:
	add_theme_constant_override("separation", 6)


func refresh() -> void:
	UI.clear(self)   # (out at once: freed later, the old screen would sit under the new one for a frame - the page jumping)
	add_child(UI.section("AUTOMATON  ·  EQUIPMENT"))
	_doll = EquipDoll.new()
	_doll.picture = picture()
	_doll.picture_scale = 0.88 if fill else 0.7
	_doll.custom_minimum_size = Vector2(470, doll_height)   # (the head and legs slots above and below the picture)
	if fill:
		_doll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_doll)
	if ModelView.available("player"):    # (the actual 3D model, turned by dragging)
		var mv := ModelView.new()
		mv.model_id = "player"
		_doll.view = mv
	for s in Gear.LOADOUT:
		var id := str(lo.get(s, ""))
		var slot := ItemSlot.make(id, 0, SLOT)
		slot.tooltip_text = "%s  ·  %s\n%s" % [Gear.AREA_OF_SLOT[s], Gear.SLOT_NAMES[s], (Gear.title(id) + "\n" + Gear.describe(id) + "\nClick (or drag it back to your items): take it off.") if id != "" else "Empty - drag %s gear here." % Gear.SLOT_KIND[s]]
		if id != "":
			slot.payload = {"src": "loadout", "slot": s, "id": id}
		slot.accepts = func(d): return d.get("src") == src and Gear.fits(str(d.get("id", "")), s)
		slot.on_drop = func(d): take_from_grid(str(d["id"]), s)
		slot.gui_input.connect(_slot_input.bind(s))
		slot.clicked.connect(func(_id): take_off(s))
		var place: Array = PLACES[s]
		_doll.add_group(s, Gear.AREA_OF_SLOT[s].to_upper(), place[0], place[1], place[2], [slot])
	if not fill:   # (the Automaton's own page: no how-to line - the tutorial's)
		add_child(UI.note(HINT, 12, 420))
	_stats = UI.label(summary(lo), 13, UI.TEXT_DIM)
	if fill:
		_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats.custom_minimum_size = Vector2(420, 0)
	add_child(_stats)
	UI.scale_fonts(self, "menu")   # (rebuilt after every change: at the player's text size again, as the menu around it)


func _slot_input(event: InputEvent, s: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		take_off(s)
		accept_event()


## Takes off what's in slot `slot` into the grid. True if done (false: an
## empty slot, the standard rifle, or no room - said in the log).
func take_off(slot: String) -> bool:
	var id := str(lo.get(slot, ""))
	if id == "" or (slot == "weapon" and id == Gear.DEFAULT_LOADOUT["weapon"]):
		return false
	if not Gear.unequip(lo, inv, cap, slot):
		GameLog.post("No room to take off the %s (%d slots full)." % [Gear.title(id), cap], "danger")
		return false
	Sfx.play("pirate/loot_take", -8.0)
	_changed()
	return true


## Whether a drop on the grid is gear taken off this loadout.
func is_mine(d: Dictionary) -> bool:
	return d.get("src") == "loadout" and lo.get(str(d.get("slot", ""))) == d.get("id")


## Equips gear `id` from the grid into `slot` (or the slot it fits). True if done.
func take_from_grid(id: String, slot := "") -> bool:
	if slot == "":
		slot = Gear.slot_for(lo, id)
	if slot == "" or not Gear.equip(lo, inv, cap, id, slot):
		return false
	Sfx.play("pirate/loot_take", -8.0)
	_changed()
	return true


func _changed() -> void:
	refresh()
	if on_change.is_valid():
		on_change.call()


## What a loadout gives you, in words.
static func summary(loadout: Dictionary) -> String:
	var w := Gear.weapon_stats(str(loadout.get("weapon", Gear.DEFAULT_LOADOUT["weapon"])))
	var fx := Gear.loadout_effects(loadout)
	var dmg: float = w["damage"] * (1.0 + float(fx.get("damage_mult", 0.0)))
	var rate: float = 1.0 / (w["interval"] * maxf(0.25, 1.0 + float(fx.get("fire_rate_mult", 0.0))))
	var reach: float = w["range"] * (1.0 + float(fx.get("range_mult", 0.0)))
	var parts := ["%.0f %s damage, %.1f shots/s, reach %.0f" % [dmg, Gear.TYPE_NAMES[w["type"]].to_lower(), rate, reach],
		"health %.0f" % (100.0 + float(fx.get("max_hp", 0.0))),
		"accuracy %d%%" % roundi(clampf(Accuracy.BASE_FOOT + float(fx.get("accuracy", 0.0)), 0.2, 0.99) * 100.0)]
	if fx.get("regen_mult", 0.0) > 0.0:
		parts.append("healing +%d%%" % roundi(fx["regen_mult"] * 100.0))
	if fx.get("speed_mult", 0.0) > 0.0:
		parts.append("speed +%d%%" % roundi(fx["speed_mult"] * 100.0))
	var res := []
	for t in Gear.DAMAGE_TYPES:
		var r := clampf(float(fx.get("resist_" + t, 0.0)), 0.0, Gear.RESIST_CAP)
		if r > 0.0:
			res.append("%s %d%%" % [t, roundi(r * 100.0)])
	if not res.is_empty():
		parts.append("resists: " + ", ".join(res))
	return "  ·  ".join(parts)
