class_name Gear
## Equipment: pieces you fit to your ship or equip on your automaton (you on
## foot), each in a quality from E (common) to A (the best), which scales
## what it does. Gear is an item like any other - "gear:<kind>:<quality>",
## e.g. "gear:plasma_rifle:3" (a Plasma Rifle B): it sits in your hold or what
## you carry (stacks of the same kind and quality), is bought at stations'
## outfitters, dropped by ships, pirates and beasts, and won in encounters.
##
## Ship gear: Shipyard.MODULES (internal and utility slots - stat modules,
## weapon modifiers, resistance plating, passives); fitted ones are the
## player's `modules` [{id, rating}]. Ship weapons stay on the hardpoints.
## Automaton gear: FOOT below, worn in the loadout (LOADOUT slots, the
## player's "loadout" {slot: item id}).
##
## Damage has a type (DAMAGE_TYPES); resistances ("resist_<type>", a share
## of that damage taken off, up to RESIST_CAP) come from gear and the tech
## tree. Heat and cold resistance also offset a planet's environment
## (Planets.environment: Akrotiri's heat, the ice moons' footing).

const PREFIX := "gear:"
const QUALITY := ["E", "D", "C", "B", "A"]
const QUALITY_NAMES := ["Common", "Fine", "Superior", "Rare", "Masterwork"]
const QUALITY_COLORS := [Color(0.75, 0.78, 0.82), Color(0.45, 0.9, 0.5), Color(0.4, 0.7, 1.0), Color(0.75, 0.5, 1.0), Color(1.0, 0.7, 0.25)]
## What a step of quality does to an effect (the outfitters' ratings: Shipyard.RATING_MULT).
const EFFECT_MULT := [1.0, 1.3, 1.65, 2.05, 2.5]
## ... and to a weapon's damage.
const WEAPON_MULT := [1.0, 1.15, 1.3, 1.45, 1.6]
const PRICE_MULT := [1.0, 2.4, 5.5, 12.0, 26.0]
## Selling gear back: this share of its price.
const SELL_SHARE := 0.6

const DAMAGE_TYPES := ["energy", "kinetic", "explosive", "heat", "cold", "electric", "beam"]
const TYPE_NAMES := {"energy": "Energy", "kinetic": "Kinetic", "explosive": "Explosive", "heat": "Heat", "cold": "Cold", "electric": "Electric", "beam": "Beam"}
## How a damage type splits between shields and hull: [x on shields, x on the
## hull once they're down]. Most hit both the same (the Pulse Cannon); a
## beam (the Beam Emitter) drains shields fast and barely scratches a hull.
const SHIELD_HULL := {"beam": [2.0, 0.35]}


## A hit of `amount` (type `dtype`) on `shields`: [taken off the shields,
## left for the hull] - after SHIELD_HULL.
static func split(dtype: String, shields: float, amount: float) -> Vector2:
	var k: Array = SHIELD_HULL.get(dtype, [1.0, 1.0])
	var on_shields := minf(shields, amount * float(k[0]))
	var left := amount - on_shields / float(k[0])
	return Vector2(on_shields, maxf(0.0, left) * float(k[1]))
const RESIST_CAP := 0.75

## The automaton's loadout: its slots, and which kind of gear each takes.
const LOADOUT := ["weapon", "mod1", "mod2", "armour", "core", "passive1", "passive2"]
const SLOT_KIND := {"weapon": "weapon", "mod1": "mod", "mod2": "mod", "armour": "armour", "core": "core",
	"passive1": "passive", "passive2": "passive"}
const SLOT_NAMES := {"weapon": "Weapon", "mod1": "Weapon mod", "mod2": "Weapon mod", "armour": "Armour",
	"core": "Core", "passive1": "Passive", "passive2": "Passive"}
const DEFAULT_LOADOUT := {"weapon": "gear:laser_rifle:0"}
## Where each slot is on the automaton (its equipment screen: EquipDoll) - the
## rifle in its right arm, a mod in its right hand, the other on its left arm,
## armour on the torso, the core in the head, passives in the legs and back.
const AREA_OF_SLOT := {"weapon": "Right arm", "mod1": "Right hand", "mod2": "Left arm", "armour": "Torso",
	"core": "Head", "passive1": "Legs", "passive2": "Back"}

## Automaton gear: kind -> {slot kind, name, price (quality E), desc, and
## for weapons damage / interval (s) / range / type / bolt colour; for the
## rest `effects` per quality step (times EFFECT_MULT)}.
## Effect keys: max_hp (flat), damage_mult, fire_rate_mult (negative: faster),
## range_mult, regen_mult, speed_mult, overcharge_mult, resist_<type>.
const FOOT := {
	"laser_rifle": {"slot": "weapon", "name": "Laser Rifle", "price": 300, "damage": 14.0, "interval": 0.22, "range": 700.0,
		"type": "energy", "color": Color(1.0, 0.55, 0.2), "desc": "The automaton's standard rifle: quick laser bolts."},
	"pulse_carbine": {"slot": "weapon", "name": "Pulse Carbine", "price": 500, "damage": 8.0, "interval": 0.11, "range": 560.0,
		"type": "energy", "color": Color(0.4, 0.9, 1.0), "desc": "A storm of light bolts, close in."},
	"plasma_rifle": {"slot": "weapon", "name": "Plasma Rifle", "price": 800, "damage": 26.0, "interval": 0.38, "range": 650.0,
		"type": "heat", "color": Color(1.0, 0.35, 0.15), "desc": "Slow, searing plasma: heat damage."},
	"rail_rifle": {"slot": "weapon", "name": "Rail Rifle", "price": 1100, "damage": 44.0, "interval": 0.7, "range": 950.0,
		"type": "kinetic", "color": Color(0.85, 0.9, 1.0), "desc": "A magnetic slug: the longest reach, the heaviest hit."},
	"cryo_rifle": {"slot": "weapon", "name": "Cryo Rifle", "price": 900, "damage": 18.0, "interval": 0.28, "range": 680.0,
		"type": "cold", "color": Color(0.6, 0.85, 1.0), "desc": "Freezing bolts: cold damage."},
	"scope": {"slot": "mod", "name": "Long Scope", "price": 260, "effects": {"range_mult": 0.08},
		"desc": "Weapon mod: more reach."},
	"amplifier": {"slot": "mod", "name": "Bolt Amplifier", "price": 340, "effects": {"damage_mult": 0.07},
		"desc": "Weapon mod: harder-hitting shots."},
	"capacitor": {"slot": "mod", "name": "Rapid Capacitor", "price": 360, "effects": {"fire_rate_mult": -0.06},
		"desc": "Weapon mod: shoots faster."},
	"stabiliser": {"slot": "mod", "name": "Gyro Stabiliser", "price": 420, "effects": {"damage_mult": 0.04, "range_mult": 0.04},
		"desc": "Weapon mod: steadier aim - a little more damage and reach."},
	"bronze_plating": {"slot": "armour", "name": "Bronze Plating", "price": 300, "effects": {"max_hp": 14.0, "resist_kinetic": 0.04},
		"desc": "Armour: more health, turns claws and slugs."},
	"ceramic_carapace": {"slot": "armour", "name": "Ceramic Carapace", "price": 450, "effects": {"max_hp": 10.0, "resist_energy": 0.06, "resist_heat": 0.03},
		"desc": "Armour: glazed ceramic that scatters laser bolts."},
	"insulated_shell": {"slot": "armour", "name": "Insulated Shell", "price": 420, "effects": {"max_hp": 8.0, "resist_cold": 0.07, "resist_heat": 0.06},
		"desc": "Armour: keeps out the cold of the ice and the heat of the magma."},
	"blast_harness": {"slot": "armour", "name": "Blast Harness", "price": 400, "effects": {"max_hp": 12.0, "resist_explosive": 0.08},
		"desc": "Armour: shrugs off blasts."},
	"standard_core": {"slot": "core", "name": "Repair Core", "price": 300, "effects": {"regen_mult": 0.15},
		"desc": "Core: you heal faster out of a fight."},
	"servo_core": {"slot": "core", "name": "Servo Core", "price": 380, "effects": {"speed_mult": 0.05},
		"desc": "Core: you walk faster."},
	"fusion_core": {"slot": "core", "name": "Fusion Core", "price": 520, "effects": {"regen_mult": 0.08, "overcharge_mult": 0.15, "max_hp": 6.0},
		"desc": "Core: energy cells overcharge longer; a little more health and healing."},
	"med_injector": {"slot": "passive", "name": "Med Injector", "price": 280, "effects": {"regen_mult": 0.12},
		"desc": "Passive: faster healing."},
	"heat_sink": {"slot": "passive", "name": "Heat Sink", "price": 300, "effects": {"resist_heat": 0.08},
		"desc": "Passive: heat resistance (and Akrotiri's heat wears on you less)."},
	"thermal_lining": {"slot": "passive", "name": "Thermal Lining", "price": 300, "effects": {"resist_cold": 0.08},
		"desc": "Passive: cold resistance (and the ice slows you less)."},
	"targeting_ai": {"slot": "passive", "name": "Targeting AI", "price": 460, "effects": {"damage_mult": 0.03, "range_mult": 0.03},
		"desc": "Passive: a little more damage and reach."},
	"reinforced_frame": {"slot": "passive", "name": "Reinforced Frame", "price": 340, "effects": {"max_hp": 9.0},
		"desc": "Passive: more health."},
}


# --- Item ids ---------------------------------------------------------------------------

static func item_id(kind: String, quality: int) -> String:
	return "%s%s:%d" % [PREFIX, kind, clampi(quality, 0, QUALITY.size() - 1)]


static func is_gear(id: String) -> bool:
	return id.begins_with(PREFIX)


## [kind, quality] of a gear item id, or [] if it isn't one (or unknown).
static func parse(id: String) -> Array:
	if not is_gear(id):
		return []
	var parts := id.substr(PREFIX.length()).split(":")
	if parts.size() != 2 or not (FOOT.has(parts[0]) or Shipyard.MODULES.has(parts[0])):
		return []
	return [parts[0], clampi(int(parts[1]), 0, QUALITY.size() - 1)]


## "ship" or "foot" (or "" if it isn't gear).
static func side(id: String) -> String:
	var p := parse(id)
	if p.is_empty():
		return ""
	return "foot" if FOOT.has(p[0]) else "ship"


## The catalogue entry of a gear item's kind ({} if none).
static func entry(id: String) -> Dictionary:
	var p := parse(id)
	if p.is_empty():
		return {}
	return FOOT[p[0]] if FOOT.has(p[0]) else Shipyard.MODULES[p[0]]


## Its slot: automaton "weapon" / "mod" / "armour" / "core" / "passive", ship "internal" / "utility".
static func slot_of(id: String) -> String:
	return str(entry(id).get("slot", ""))


static func quality(id: String) -> int:
	var p := parse(id)
	return p[1] if not p.is_empty() else 0


static func title(id: String) -> String:
	var e := entry(id)
	return "%s %s" % [e.get("name", id), QUALITY[quality(id)]] if not e.is_empty() else id


static func price(id: String) -> int:
	var e := entry(id)
	return roundi(float(e.get("price", 0)) * PRICE_MULT[quality(id)])


## Its effects at its quality.
static func effects(id: String) -> Dictionary:
	var e := entry(id)
	var out := {}
	var m: float = EFFECT_MULT[quality(id)]
	for k in e.get("effects", {}):
		out[k] = float(e["effects"][k]) * m
	return out


## An automaton weapon's stats at its quality: {damage, interval, range, type, color}.
static func weapon_stats(id: String) -> Dictionary:
	var e := entry(id)
	if e.get("slot", "") != "weapon":
		e = FOOT["laser_rifle"]
	return {"damage": float(e["damage"]) * WEAPON_MULT[quality(id)], "interval": float(e["interval"]),
		"range": float(e["range"]), "type": str(e["type"]), "color": e["color"]}


## Items-style info for a gear item (Items.info): name, kind "gear", value, price, desc.
static func info(id: String) -> Dictionary:
	var e := entry(id)
	if e.is_empty():
		return {}
	return {"name": title(id), "kind": "gear", "value": roundi(price(id) * SELL_SHARE), "price": price(id),
		"desc": "%s %s gear (%s). %s %s" % [QUALITY_NAMES[quality(id)], "automaton" if side(id) == "foot" else "ship",
			_slot_label(id), e.get("desc", ""), describe(id)]}


static func _slot_label(id: String) -> String:
	var s := slot_of(id)
	return {"weapon": "weapon", "mod": "weapon mod", "armour": "armour", "core": "core", "passive": "passive",
		"internal": "internal slot", "utility": "utility slot"}.get(s, s)


## What it does, in words ("+14 health, +4% kinetic resistance").
static func describe(id: String) -> String:
	var parts := []
	if slot_of(id) == "weapon" and side(id) == "foot":
		var w := weapon_stats(id)
		parts.append("%.0f %s damage, %.1f shots/s, reach %.0f" % [w["damage"], TYPE_NAMES[w["type"]].to_lower(), 1.0 / w["interval"], w["range"]])
	var fx := effects(id)
	for k in fx:
		parts.append(effect_text(k, fx[k]))
	return ", ".join(parts)


static func effect_text(key: String, v: float) -> String:
	if key.begins_with("resist_"):
		return "+%d%% %s resistance" % [roundi(v * 100.0), key.trim_prefix("resist_")]
	match key:
		"max_hp": return "+%.0f health" % v
		"max_hull": return "+%.0f hull" % v
		"max_shields": return "+%.0f shields" % v
		"hull_regen": return "+%.1f hull/s" % v
		"cargo": return "+%d hold slots" % roundi(v / Shipyard.RACK_UNITS_PER_SLOT)
		"fire_rate_mult": return "+%d%% fire rate" % roundi(-v * 100.0)
	var label: String = {"damage_mult": "damage", "range_mult": "reach", "regen_mult": "healing", "speed_mult": "speed",
		"overcharge_mult": "overcharge time", "shield_regen_mult": "shield recharge", "handling_mult": "handling"}.get(key, key)
	return "+%d%% %s" % [roundi(v * 100.0), label]


# --- The automaton's loadout ---------------------------------------------------------------

## The player's loadout (the save format's "loadout": {slot: item id}), made if missing.
static func loadout(player: Dictionary) -> Dictionary:
	if not player.get("loadout") is Dictionary:
		player["loadout"] = DEFAULT_LOADOUT.duplicate()
	return player["loadout"]


## Whether gear item `id` goes in loadout slot `slot`.
static func fits(id: String, slot: String) -> bool:
	return side(id) == "foot" and SLOT_KIND.get(slot, "") == slot_of(id)


## The summed effects of a loadout (weapon included).
static func loadout_effects(lo: Dictionary) -> Dictionary:
	var total := {}
	for s in LOADOUT:
		var id := str(lo.get(s, ""))
		if id == "":
			continue
		var fx := effects(id)
		for k in fx:
			total[k] = float(total.get(k, 0.0)) + fx[k]
	return total


## Equips gear item `id` from inventory `inv` into slot `slot` of loadout
## `lo`; what was there goes back into `inv` (it needs room: `cap` slots).
## True if done.
static func equip(lo: Dictionary, inv: Dictionary, cap: int, id: String, slot: String) -> bool:
	if not fits(id, slot) or int(inv.get(id, 0)) <= 0:
		return false
	var old := str(lo.get(slot, ""))
	Inventory.take(inv, id, 1)
	if old != "" and Inventory.add(inv, old, 1, cap) < 1:
		Inventory.add(inv, id, 1, cap + 1)   # (no room for the old one: undone)
		return false
	lo[slot] = id
	return true


## The slot a piece of gear would go in: the first empty one that takes it,
## else the first that takes it ("" if none).
static func slot_for(lo: Dictionary, id: String) -> String:
	var first := ""
	for s in LOADOUT:
		if fits(id, s):
			if str(lo.get(s, "")) == "":
				return s
			if first == "":
				first = s
	return first


## Takes off what's in slot `slot` of loadout `lo` into `inv`. True if done
## (the weapon slot is never left empty: the standard rifle goes back in).
static func unequip(lo: Dictionary, inv: Dictionary, cap: int, slot: String) -> bool:
	var old := str(lo.get(slot, ""))
	if old == "" or (slot == "weapon" and old == DEFAULT_LOADOUT["weapon"]):
		return false
	if Inventory.add(inv, old, 1, cap) < 1:
		return false
	if slot == "weapon":
		lo[slot] = DEFAULT_LOADOUT["weapon"]
	else:
		lo.erase(slot)
	return true


# --- Ship gear ---------------------------------------------------------------------------

## Fits ship gear item `id` from the hold: true if it had a free slot.
static func fit(data: Node, id: String) -> bool:
	if side(id) != "ship" or data.count(id) <= 0:
		return false
	var p := parse(id)
	if Shipyard.free_for(data, id) <= 0:
		return false
	Inventory.take(data.items, id, 1)
	data.modules.append({"id": p[0], "rating": p[1]})
	return true


## Takes fitted module `i` out into the hold: true if there was room.
static func unfit(data: Node, i: int) -> bool:
	if i < 0 or i >= data.modules.size():
		return false
	var m: Dictionary = data.modules[i]
	var id := item_id(m["id"], int(m["rating"]))
	if Inventory.room_for(data.items, id, Shipyard.cargo_capacity(data)) < 1:
		return false
	Inventory.add(data.items, id, 1, Shipyard.cargo_capacity(data))
	data.modules.remove_at(i)
	return true


# --- Where gear comes from ------------------------------------------------------------------

## A random piece of gear: `side` "ship" / "foot" / "" (either); `level` 0..1
## (how tough what dropped it was: the better, the likelier a high quality).
static func roll(rng: RandomNumberGenerator, side_ := "", level := 0.3) -> String:
	var s := side_ if side_ != "" else ("ship" if rng.randf() < 0.5 else "foot")
	var kinds: Array = FOOT.keys() if s == "foot" else Shipyard.MODULES.keys()
	var kind: String = kinds[rng.randi() % kinds.size()]
	# Quality: mostly E-C; the tougher the source, the more B and A.
	var r := rng.randf() + clampf(level, 0.0, 1.0) * 0.55
	var q := 0
	for t in [0.55, 0.85, 1.12, 1.38]:
		if r > t:
			q += 1
	return item_id(kind, q)


# --- Icons --------------------------------------------------------------------------------

## A gear item's icon: a glyph for its slot in a ring of its quality's colour.
static func draw_icon(ci: CanvasItem, id: String, rect: Rect2, dim := false) -> void:
	var c := rect.get_center()
	var r := minf(rect.size.x, rect.size.y) * 0.5
	var qc: Color = QUALITY_COLORS[quality(id)]
	if dim:
		qc = qc.darkened(0.5)
	ci.draw_arc(c, r * 0.92, 0, TAU, 32, Color(qc, 0.9), maxf(1.5, r * 0.08), true)
	var g := Color(0.92, 0.94, 1.0) if not dim else Color(0.5, 0.52, 0.56)
	var w := maxf(1.5, r * 0.1)
	match slot_of(id):
		"weapon":
			ci.draw_line(c + Vector2(-r * 0.6, r * 0.25), c + Vector2(r * 0.6, -r * 0.25), g, w * 1.6, true)
			ci.draw_line(c + Vector2(-r * 0.2, r * 0.1), c + Vector2(-r * 0.3, r * 0.5), g, w, true)
		"mod":
			for k in 6:
				var a := TAU * k / 6.0
				ci.draw_line(c + Vector2.from_angle(a) * r * 0.25, c + Vector2.from_angle(a) * r * 0.55, g, w, true)
			ci.draw_arc(c, r * 0.25, 0, TAU, 16, g, w, true)
		"armour", "internal":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-r * 0.5, -r * 0.45), c + Vector2(r * 0.5, -r * 0.45),
				c + Vector2(r * 0.45, r * 0.15), c + Vector2(0, r * 0.6), c + Vector2(-r * 0.45, r * 0.15), c + Vector2(-r * 0.5, -r * 0.45)]), g, w, true)
		"core":
			ci.draw_arc(c, r * 0.45, 0, TAU, 20, g, w, true)
			ci.draw_circle(c, r * 0.18, Color(qc, 0.9))
		_:   # passive, utility
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -r * 0.55), c + Vector2(r * 0.5, 0), c + Vector2(0, r * 0.55),
				c + Vector2(-r * 0.5, 0), c + Vector2(0, -r * 0.55)]), g, w, true)
	ci.draw_string(ThemeDB.fallback_font, rect.position + Vector2(rect.size.x - r * 0.55, r * 0.55), QUALITY[quality(id)],
		HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, int(r * 0.42)), qc)
