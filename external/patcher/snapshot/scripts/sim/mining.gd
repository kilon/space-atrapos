class_name Mining
extends RefCounted
## Mining by hand. A rock is a mix of minerals (COMPOSITION by its kind, each
## rock its own share of them) and its ore lies in VEINS - seams of one
## mineral each at places on it, hidden until a prospecting scan (right-click
## the rock: ShipScanner) shows them and what the rock holds.
##
## Cutting a vein (hold the left button on the rock; click near a vein to pick
## it) heats it: below the vein's band it cuts slowly; in its band (green) it
## cuts at full speed and builds RESONANCE - the longer you hold it there the
## faster, up to RESONANCE_MAX; above the band it strains; at the top it
## FRACTURES - a share of the vein breaks off as worthless rubble and the heat
## drops. Each vein heats at its own pace (its mineral's HARDNESS). Let go to
## let it cool. Without a scan you can only hack at the bulk rock: rubble.
## Cut ore comes off as FRAGMENTS ("frag:<mineral>"): sold as they are they
## fetch little; the ship's refinery (a device aboard: DeviceMenu) turns them into the mineral.

const PREFIX := "frag:"
## Minerals veins are made of (Items ids: the market's ores and minerals); hardness heats a vein faster.
const MINERALS := {
	"iron_ore": {"hard": 1.0}, "titanium_ore": {"hard": 1.25}, "platinum_ore": {"hard": 1.45}, "ice": {"hard": 0.7},
	"copper_ore": {"hard": 0.9}, "tin_ore": {"hard": 0.85}, "silver_ore": {"hard": 1.1}, "gold_ore": {"hard": 1.2},
	"cobalt": {"hard": 1.3}, "sulphur": {"hard": 0.75}, "obsidian": {"hard": 1.15}, "salt": {"hard": 0.7}, "orichalcum": {"hard": 1.6},
}
## A rock kind's minerals and their usual shares (each rock varies round these).
const COMPOSITION := {
	"iron": {"iron_ore": 0.6, "copper_ore": 0.15, "tin_ore": 0.12, "sulphur": 0.08, "cobalt": 0.05},
	"titanium": {"titanium_ore": 0.55, "cobalt": 0.15, "silver_ore": 0.12, "obsidian": 0.12, "orichalcum": 0.06},
	"platinum": {"platinum_ore": 0.45, "gold_ore": 0.2, "silver_ore": 0.15, "orichalcum": 0.1, "cobalt": 0.1},
	"ice": {"ice": 0.75, "sulphur": 0.1, "salt": 0.1, "obsidian": 0.05},
}
## The heat model (per second, at hardness 1): firing heats, it always cools.
const HEAT := 0.42
const COOL := 0.2
const BAND := Vector2(0.55, 0.82)     # the cutting band (green)
const SLOW_FROM := 0.3                # below this it doesn't cut
const RATE := 3.6                     # fragments a second in the band (resonance 1)
const RESONANCE_RATE := 0.3           # resonance a second, held in the band
const RESONANCE_MAX := 1.6
const FRACTURE_LOSS := 0.25           # of what's left in the vein, lost as rubble
const FRAG_SHARE := 0.4               # a fragment sells for this share of its mineral


## A rock's veins and composition, from its kind, size and seed: {comp: {mineral: share}, veins: [...]}.
## A vein: {a (angle on the rock), d (its distance out, x radius), mineral, units, max, heat, res}.
static func generate(kind: String, radius: float, ore_total: int, seed_n: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n * 31 + 7
	var base: Dictionary = COMPOSITION.get(kind, COMPOSITION["iron"])
	var comp := {}
	var sum := 0.0
	for m in base:
		var v: float = float(base[m]) * rng.randf_range(0.6, 1.4)
		comp[m] = v
		sum += v
	for m in comp:
		comp[m] = comp[m] / sum
	var n := clampi(2 + int(radius / 32.0), 2, 5)
	var veins := []
	var vein_units := int(ore_total * 0.75)
	var minerals: Array = comp.keys()
	minerals.sort_custom(func(a, b): return comp[a] > comp[b])
	for i in n:
		# (the first the main mineral; the rest drawn by share)
		var m: String = minerals[0]
		if i > 0:
			var r := rng.randf()
			for k in minerals:
				r -= float(comp[k])
				if r <= 0.0:
					m = k
					break
		var units := maxi(4, int(vein_units * (0.45 if i == 0 else 0.55 / (n - 1)) * rng.randf_range(0.8, 1.2)))
		veins.append({"a": TAU * (i + rng.randf_range(0.15, 0.85)) / n, "d": rng.randf_range(0.35, 0.72), "mineral": m,
			"units": units, "max": units, "heat": 0.0, "res": 1.0, "acc": 0.0, "len": rng.randf_range(0.25, 0.45)})
	return {"comp": comp, "veins": veins}


## How fast a vein cuts at its heat (0: not at all).
static func cut_rate(heat: float) -> float:
	if heat < SLOW_FROM:
		return 0.0
	if heat < BAND.x:
		return 0.3
	if heat <= BAND.y:
		return 1.0
	return 0.7


static func in_band(heat: float) -> bool:
	return heat >= BAND.x and heat <= BAND.y


# --- Fragments: items "frag:<mineral>" ("frag:rubble": broken rock) --------------------------------

static func frag_id(mineral: String) -> String:
	return PREFIX + mineral


static func is_frag(id: String) -> bool:
	return id.begins_with(PREFIX)


static func mineral_of(id: String) -> String:
	return id.substr(PREFIX.length()) if is_frag(id) else ""


static func valid(id: String) -> bool:
	var m := mineral_of(id)
	return m == "rubble" or MINERALS.has(m)


static func info(id: String) -> Dictionary:
	if not valid(id):
		return {}
	var m := mineral_of(id)
	if m == "rubble":
		return {"name": "Rubble", "kind": "cargo", "value": 1,
			"desc": "Broken rock from a fractured vein or the bulk of an unscanned asteroid. A refinery gets a little scrap and the odd mineral out of it."}
	var mi: Dictionary = Items.ITEMS.get(m, {})
	return {"name": "%s Fragments" % str(mi.get("name", m)).replace(" Ore", ""), "kind": "cargo",
		"value": maxi(1, roundi(float(mi.get("value", 10)) * FRAG_SHARE)),
		"desc": "Cut from an asteroid's vein: %s in raw rock. Your ship's refinery (its terminal in the cargo bay) turns each into a unit of %s - sold as they are they fetch little." % [str(mi.get("name", m)).to_lower(), str(mi.get("name", m)).to_lower()]}


## A fragment's icon: a jagged chunk in its mineral's colours, with a glint of it.
static func draw_icon(ci: CanvasItem, id: String, rect: Rect2, dim := false) -> void:
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) * 0.5
	var a := 0.4 if dim else 1.0
	var m := mineral_of(id)
	var col := mineral_color(m)
	var pts := PackedVector2Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(m)
	for k in 7:
		pts.append(c + Vector2.from_angle(TAU * k / 7.0 + 0.3) * s * rng.randf_range(0.55, 0.8))
	ci.draw_colored_polygon(pts, Color(0.32, 0.29, 0.27, a))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.55 + Vector2(-0.08, -0.08) * s)
	if m != "rubble":
		ci.draw_colored_polygon(inner, Color(col, 0.85 * a))
		ci.draw_line(c + Vector2(-0.3, -0.25) * s, c + Vector2(0.2, 0.1) * s, Color(col.lightened(0.5), a), maxf(1.0, s * 0.08), true)
	pts.append(pts[0])
	ci.draw_polyline(pts, Color(0, 0, 0, 0.6 * a), maxf(1.0, s * 0.06), true)


static func mineral_color(m: String) -> Color:
	match m:
		"iron_ore": return Color(0.85, 0.48, 0.3)
		"titanium_ore": return Color(0.4, 0.88, 1.0)
		"platinum_ore": return Color(0.9, 0.9, 0.95)
		"ice": return Color(0.7, 0.92, 1.0)
		"copper_ore": return Color(0.9, 0.55, 0.3)
		"tin_ore": return Color(0.7, 0.72, 0.68)
		"silver_ore": return Color(0.85, 0.88, 0.92)
		"gold_ore": return Color(1.0, 0.82, 0.3)
		"cobalt": return Color(0.3, 0.45, 1.0)
		"sulphur": return Color(0.95, 0.9, 0.3)
		"obsidian": return Color(0.35, 0.3, 0.45)
		"salt": return Color(0.95, 0.95, 0.92)
		"orichalcum": return Color(1.0, 0.55, 0.35)
	return Color(0.6, 0.55, 0.5)
