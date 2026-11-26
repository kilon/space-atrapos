class_name Skills
extends RefCounted
## The automaton's skills on foot: martial arts, the leap, and the arcana -
## what goes on the 9-slot toolbar as "skill:<id>" (PlanetSurface.use_skill
## performs them; SkillFx draws the spells; the Spell Book - the Field
## Computer's SKILLS tab, SkillBookPage - is where you learn and raise them).
##
## Martial arts are STYLES: each a chain of blows (MOVES) thrown one after the
## other while you fight in it - click an enemy, or use the style from the
## toolbar, and the automaton closes in and works through the chain until the
## enemy falls. Higher ranks add the chain's later blows.
##   pygmachia   the boxer's art: jab, cross, hook, uppercut
##   pankration  every limb a weapon: elbow, knee, front kick, force palm
##   laktisma    the kicker's art: side kick, roundhouse, spinning back kick
## and single techniques: sweep (all around you, knocks down), comet (a flying
## kick across the gap), guard (brace: most of the damage shrugged off).
## Movement: leap - a flip through the air to where you point: bolts fired at
## you while you're up miss.
## Arcana: lance (a beam through everything in a line), phlox (a fireball that
## bursts and burns), keraunos (lightning from the sky, leaping on to others),
## aegis (a dome that soaks up damage), eidola (spectral fighters at your side).
##
## Levels: fighting earns experience (XP: defeating enemies, blows and spells
## that land); each level (to MAX_LEVEL) gives a skill point, spent in the
## Spell Book to learn a skill (it needs your level: "level") or raise its
## rank (to MAX_RANK): more damage (RANK_DAMAGE a rank), shorter cooldowns
## (RANK_COOLDOWN), and what each skill's "ranks" lines say. Every use costs
## stamina (Stamina). Kept with the player: "skills" {level, xp, points, ranks}.

const PREFIX := "skill:"
const MAX_RANK := 5
const MAX_LEVEL := 20
const RANK_DAMAGE := 0.2
const RANK_COOLDOWN := 0.07
const START := {"pygmachia": 1, "leap": 1, "phlox": 1}
const START_POINTS := 2
const START_BAR := ["pygmachia", "leap", "phlox"]
const MELEE_REACH := 78.0          # px: a blow lands within it
const COMBO_WINDOW := 1.1          # s after a blow the chain goes on (else it starts over)
const XP_BLOW := 2
const XP_SPELL := 5

const SCHOOLS := [
	["martial", "Martial arts", Color(1.0, 0.62, 0.3)],
	["motion", "Movement", Color(0.5, 0.95, 0.6)],
	["arcana", "Arcana", Color(0.55, 0.75, 1.0)],
]

## A blow: its clip, damage, how far it shoves (px), how long it staggers (s);
## "down": it floors them; "arc": everyone within reach in front, not just the
## target ("ring": all around).
const MOVES := {
	"jab": {"name": "Jab", "clip": "jab", "damage": 14.0, "push": 6.0, "stagger": 0.25},
	"cross": {"name": "Cross", "clip": "cross", "damage": 20.0, "push": 12.0, "stagger": 0.35},
	"hook": {"name": "Hook", "clip": "hook", "damage": 24.0, "push": 10.0, "stagger": 0.45},
	"uppercut": {"name": "Uppercut", "clip": "uppercut", "damage": 32.0, "push": 26.0, "stagger": 0.6, "down": true},
	"elbow": {"name": "Elbow", "clip": "elbow", "damage": 19.0, "push": 8.0, "stagger": 0.35},
	"knee": {"name": "Knee", "clip": "knee", "damage": 25.0, "push": 10.0, "stagger": 0.5},
	"front": {"name": "Front kick", "clip": "front", "damage": 26.0, "push": 60.0, "stagger": 0.5},
	"palm": {"name": "Force palm", "clip": "palm", "damage": 34.0, "push": 120.0, "stagger": 0.9, "down": true},
	"side": {"name": "Side kick", "clip": "side", "damage": 26.0, "push": 80.0, "stagger": 0.5},
	"round": {"name": "Roundhouse", "clip": "round", "damage": 29.0, "push": 30.0, "stagger": 0.5, "arc": true},
	"spin": {"name": "Spinning back kick", "clip": "spin", "damage": 40.0, "push": 90.0, "stagger": 0.8, "arc": true, "down": true},
	"sweep": {"name": "Sweep", "clip": "sweep", "damage": 22.0, "push": 14.0, "stagger": 1.5, "ring": true, "down": true},
	"comet": {"name": "Comet kick", "clip": "flykick", "damage": 45.0, "push": 110.0, "stagger": 1.0, "down": true},
}

const SKILLS := {
	"pygmachia": {"name": "Pygmachia", "school": "martial", "kind": "style", "level": 1, "stamina": 1.0, "cooldown": 0.0,
		"moves": ["jab", "cross", "hook", "uppercut"], "open": [2, 3, 4, 4, 4],
		"desc": "The boxer's art. Fast hands: a jab and a cross, then a hook, then an uppercut that floors them.",
		"ranks": ["Jab, cross", "+ Hook", "+ Uppercut (knocks down)", "+20% damage", "+20% damage"]},
	"pankration": {"name": "Pankration", "school": "martial", "kind": "style", "level": 2, "stamina": 1.2, "cooldown": 0.0,
		"moves": ["elbow", "knee", "front", "palm"], "open": [2, 3, 4, 4, 4],
		"desc": "Every limb a weapon. An elbow and a knee up close, a front kick that drives them back, a force palm that throws them.",
		"ranks": ["Elbow, knee", "+ Front kick (shoves)", "+ Force palm (throws, knocks down)", "+20% damage", "+20% damage"]},
	"laktisma": {"name": "Laktisma", "school": "martial", "kind": "style", "level": 4, "stamina": 1.5, "cooldown": 0.0,
		"moves": ["side", "round", "spin"], "open": [2, 2, 3, 3, 3],
		"desc": "The kicker's art. A side kick, a roundhouse that catches everyone in front of you, a spinning back kick.",
		"ranks": ["Side kick, roundhouse (hits all in front)", "+20% damage", "+ Spinning back kick (knocks down)", "+20% damage", "+20% damage"]},
	"sweep": {"name": "Scythe Sweep", "school": "martial", "kind": "move", "move": "sweep", "level": 5, "stamina": 5.0, "cooldown": 6.0,
		"desc": "Drop low and spin a leg through everyone around you: they all go down.",
		"ranks": ["Knocks down all around you", "+20% damage", "+20% damage, wider", "+20% damage", "+20% damage, wider"]},
	"comet": {"name": "Comet Kick", "school": "martial", "kind": "move", "move": "comet", "level": 7, "stamina": 6.0, "cooldown": 7.0,
		"range": 340.0,
		"desc": "A flying kick across the gap: you cross to an enemy in one bound and land on it, foot first.",
		"ranks": ["A flying kick from 340 px", "+20% damage", "+20% damage, from further", "+20% damage", "+20% damage, from further"]},
	"guard": {"name": "Aspis Guard", "school": "martial", "kind": "guard", "level": 2, "stamina": 2.0, "cooldown": 4.0, "time": 1.5,
		"soak": 0.6,
		"desc": "Arms up, braced: for a moment most of what hits you is shrugged off.",
		"ranks": ["60% of damage shrugged off for 1.5 s", "65%", "70%, longer", "75%", "80%, longer"]},
	"leap": {"name": "Hermes' Leap", "school": "motion", "kind": "leap", "level": 1, "stamina": 4.0, "cooldown": 5.0, "range": 380.0,
		"desc": "A flip through the air to where you point - over gaps in the fight, onto an enemy, out of a crossfire. Shots fired at you while you're up miss.",
		"ranks": ["Leaps up to 380 px", "Further", "Landing staggers those around", "Further", "The landing hits hard"]},
	"lance": {"name": "Helios Lance", "school": "arcana", "kind": "beam", "level": 3, "stamina": 6.0, "cooldown": 6.0, "range": 720.0,
		"damage": 26.0, "ticks": 3,
		"desc": "A beam of light from your palms, through everything in a line.",
		"ranks": ["A beam through all in its line", "+20% damage", "+20% damage, a wider beam", "+20% damage", "+20% damage, a wider beam"]},
	"phlox": {"name": "Phlox", "school": "arcana", "kind": "fireball", "level": 1, "stamina": 5.0, "cooldown": 4.5, "range": 640.0,
		"damage": 44.0, "radius": 105.0, "burn": 4.0, "burn_time": 4.0,
		"desc": "A ball of fire that bursts where it lands and leaves them burning.",
		"ranks": ["Bursts over 105 px, burns for 4 s", "+20% damage", "+20% damage, a wider burst", "+20% damage", "+20% damage, a wider burst"]},
	"keraunos": {"name": "Keraunos", "school": "arcana", "kind": "lightning", "level": 6, "stamina": 7.0, "cooldown": 8.0, "range": 600.0,
		"damage": 60.0, "stun": 0.8, "chain_range": 210.0,
		"desc": "Call the thunderbolt down on one of them; it leaps on to others near, at half strength.",
		"ranks": ["Strikes one, leaps to 1 more", "Leaps to 2", "Leaps to 3", "Leaps to 4", "Leaps to 5"]},
	"aegis": {"name": "Aegis Dome", "school": "arcana", "kind": "dome", "level": 8, "stamina": 8.0, "cooldown": 18.0, "time": 6.0,
		"soak": 60.0, "radius": 120.0, "damage": 10.0,
		"desc": "A dome of force around you: it throws back those standing too close and soaks up what's thrown at you until it breaks.",
		"ranks": ["Soaks 60 damage, 6 s", "85, 7 s", "110, 8 s", "135, 9 s", "160, 10 s"]},
	"eidola": {"name": "Eidola", "school": "arcana", "kind": "minions", "level": 10, "stamina": 12.0, "cooldown": 30.0, "time": 18.0,
		"damage": 10.0,
		"desc": "Call up spectral fighters out of the ground: they go for your enemies with their fists and feet, and draw their fire.",
		"ranks": ["1 eidolon, 18 s", "20 s, they hit harder", "2 eidola", "24 s, they hit harder", "3 eidola"]},
}

const ORDER := ["pygmachia", "pankration", "laktisma", "guard", "sweep", "comet", "leap", "phlox", "lance", "keraunos", "aegis", "eidola"]


# --- Items (the toolbar) -----------------------------------------------------------------

static func is_skill(item: String) -> bool:
	return item.begins_with(PREFIX)


static func id_of(item: String) -> String:
	return item.substr(PREFIX.length()) if is_skill(item) else ""


static func item_of(id: String) -> String:
	return PREFIX + id


static func valid(item: String) -> bool:
	return SKILLS.has(id_of(item))


static func info(item: String) -> Dictionary:
	var s: Dictionary = SKILLS.get(id_of(item), {})
	if s.is_empty():
		return {}
	return {"name": s["name"], "kind": "skill", "value": 0, "desc": s["desc"]}


# --- The player's skills -----------------------------------------------------------------

## The player's skills (made the first time: the starting ones, on the toolbar's free slots).
static func state(player: Dictionary) -> Dictionary:
	var st = player.get("skills")
	if not st is Dictionary or not st.get("ranks") is Dictionary:
		st = {"level": 1, "xp": 0, "points": START_POINTS, "ranks": START.duplicate()}
		player["skills"] = st
		var bar: Array = Inventory.toolbar(player, true)
		for id in START_BAR:
			var it := item_of(id)
			if bar.has(it):
				continue
			var free := bar.find("")
			if free >= 0:
				bar[free] = it
	return st


## A saved "skills" made safe (PlayerData.load_save_data).
static func clean(d: Variant) -> Dictionary:
	if not d is Dictionary or not d.get("ranks") is Dictionary:
		return {}
	var ranks := {}
	for id in d["ranks"]:
		if SKILLS.has(str(id)):
			ranks[str(id)] = clampi(int(d["ranks"][id]), 0, MAX_RANK)
	return {"level": clampi(int(d.get("level", 1)), 1, MAX_LEVEL), "xp": maxi(0, int(d.get("xp", 0))),
		"points": maxi(0, int(d.get("points", 0))), "ranks": ranks}


static func rank(player: Dictionary, id: String) -> int:
	return int(state(player)["ranks"].get(id, 0))


static func level(player: Dictionary) -> int:
	return int(state(player)["level"])


## XP from one level to the next.
static func xp_need(lvl: int) -> int:
	return roundi(60.0 * pow(float(lvl), 1.3))


## What defeating something is worth (its health).
static func xp_for_kill(max_hp: float) -> int:
	return clampi(roundi(max_hp * 0.5), 8, 400)


## Adds experience; returns the levels gained (a skill point each).
static func add_xp(player: Dictionary, n: int) -> int:
	var st := state(player)
	if int(st["level"]) >= MAX_LEVEL:
		return 0
	st["xp"] = int(st["xp"]) + maxi(0, n)
	var gained := 0
	while int(st["level"]) < MAX_LEVEL and int(st["xp"]) >= xp_need(int(st["level"])):
		st["xp"] = int(st["xp"]) - xp_need(int(st["level"]))
		st["level"] = int(st["level"]) + 1
		st["points"] = int(st["points"]) + 1
		gained += 1
	if int(st["level"]) >= MAX_LEVEL:
		st["xp"] = 0
	return gained


## Why a skill can't be learned / raised now ("" - it can).
static func cant_learn(player: Dictionary, id: String) -> String:
	var st := state(player)
	if not SKILLS.has(id):
		return "No such skill."
	var r := int(st["ranks"].get(id, 0))
	if r >= MAX_RANK:
		return "At its highest rank."
	if int(st["level"]) < int(SKILLS[id]["level"]):
		return "Needs level %d." % int(SKILLS[id]["level"])
	if int(st["points"]) <= 0:
		return "No skill points - fight to earn a level."
	return ""


## Spends a point: learns the skill, or raises its rank. True if it did.
static func learn(player: Dictionary, id: String) -> bool:
	if cant_learn(player, id) != "":
		return false
	var st := state(player)
	st["points"] = int(st["points"]) - 1
	st["ranks"][id] = int(st["ranks"].get(id, 0)) + 1
	return true


# --- What a rank does --------------------------------------------------------------------

static func damage_mult(r: int) -> float:
	return 1.0 + RANK_DAMAGE * maxi(0, r - 1)


static func cooldown(id: String, r: int) -> float:
	return float(SKILLS[id].get("cooldown", 0.0)) * (1.0 - RANK_COOLDOWN * maxi(0, r - 1))


static func stamina(id: String) -> float:
	return float(SKILLS[id].get("stamina", 0.0))


## A style's blows at a rank.
static func chain(id: String, r: int) -> Array:
	var s: Dictionary = SKILLS[id]
	var n: int = s["open"][clampi(r, 1, MAX_RANK) - 1]
	return (s["moves"] as Array).slice(0, n)


## A blow's damage at a skill's rank.
static func blow_damage(move: String, r: int) -> float:
	return float(MOVES[move]["damage"]) * damage_mult(r)


static func reach(id: String, r: int) -> float:
	var base := float(SKILLS[id].get("range", 0.0))
	match id:
		"leap":
			return base + 45.0 * (int(r >= 2) + int(r >= 4))
		"comet":
			return base + 50.0 * (int(r >= 3) + int(r >= 5))
	return base


## A spell's numbers at a rank: {damage, radius, time, soak, count, chains, width...}.
static func spell(id: String, r: int) -> Dictionary:
	var s: Dictionary = SKILLS[id]
	var out := {"damage": float(s.get("damage", 0.0)) * damage_mult(r), "range": reach(id, r)}
	match id:
		"lance":
			out["width"] = 26.0 + 9.0 * (int(r >= 3) + int(r >= 5))
			out["ticks"] = int(s["ticks"])
		"phlox":
			out["radius"] = float(s["radius"]) + 20.0 * (int(r >= 3) + int(r >= 5))
			out["burn"] = float(s["burn"]) * damage_mult(r)
			out["burn_time"] = float(s["burn_time"])
		"keraunos":
			out["chains"] = r
			out["stun"] = float(s["stun"])
			out["chain_range"] = float(s["chain_range"])
		"aegis":
			out["soak"] = float(s["soak"]) + 25.0 * (r - 1)
			out["time"] = float(s["time"]) + 1.0 * (r - 1)
			out["radius"] = float(s["radius"])
		"eidola":
			out["count"] = 1 + int(r >= 3) + int(r >= 5)
			out["time"] = float(s["time"]) + 2.0 * (int(r >= 2) + int(r >= 4)) + 2.0 * int(r >= 4)
			out["damage"] = float(s["damage"]) * (1.0 + 0.3 * (int(r >= 2) + int(r >= 4)))
		"guard":
			out["soak"] = float(s["soak"]) + 0.05 * (r - 1)
			out["time"] = float(s["time"]) + 0.4 * (int(r >= 3) + int(r >= 5))
		"sweep":
			out["radius"] = 100.0 + 18.0 * (int(r >= 3) + int(r >= 5))
		"leap":
			out["shock"] = 0.0 if r < 3 else (14.0 if r < 5 else 34.0)
	return out


## A skill's lines for the Spell Book / a tooltip: what it is, its cost, its ranks
## (the ones you have marked).
static func describe(id: String, r: int) -> String:
	var s: Dictionary = SKILLS[id]
	var lines := PackedStringArray()
	lines.append(str(s["desc"]))
	var cost := "Stamina %s%s" % [str(snappedf(stamina(id), 0.1)).trim_suffix(".0"), " a blow" if s["kind"] == "style" else ""]
	var cd := cooldown(id, maxi(1, r))
	if cd > 0.0:
		cost += "  ·  cooldown %s s" % str(snappedf(cd, 0.1)).trim_suffix(".0")
	lines.append(cost)
	for i in MAX_RANK:
		lines.append("%s Rank %d: %s" % ["●" if i < r else "○", i + 1, s["ranks"][i]])
	return "\n".join(lines)


static func school_color(id: String) -> Color:
	var sc := str(SKILLS.get(id, {}).get("school", ""))
	for s in SCHOOLS:
		if s[0] == sc:
			return s[2]
	return Color.WHITE


# --- Icons -------------------------------------------------------------------------------

static func draw_icon(ci: CanvasItem, item: String, rect: Rect2, dim := false) -> void:
	var id := id_of(item) if is_skill(item) else item
	var a := 0.35 if dim else 1.0
	var c := rect.get_center()
	var s := minf(rect.size.x, rect.size.y) / 2.0
	var col := school_color(id)
	var ink := Color(col, a)
	var hot := Color(1.0, 0.95, 0.8, a)
	# a medallion in the school's colour
	ci.draw_circle(c, s * 0.98, Color(col.darkened(0.78), 0.95 * a))
	ci.draw_arc(c, s * 0.94, 0, TAU, 28, Color(col, 0.85 * a), maxf(1.5, s * 0.09), true)
	var w := maxf(2.0, s * 0.16)
	match id:
		"pygmachia":   # a fist
			ci.draw_rect(Rect2(c + Vector2(-0.38, -0.3) * s, Vector2(0.72, 0.56) * s), ink)
			for k in 4:
				ci.draw_rect(Rect2(c + Vector2(-0.38 + k * 0.185, -0.48) * s, Vector2(0.15, 0.24) * s), hot)
			ci.draw_rect(Rect2(c + Vector2(-0.56, -0.12) * s, Vector2(0.24, 0.3) * s), hot)
			ci.draw_rect(Rect2(c + Vector2(-0.2, 0.26) * s, Vector2(0.4, 0.3) * s), Color(col.darkened(0.3), a))
		"pankration":  # a bent arm: the elbow
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.5, 0.45) * s, c + Vector2(0.35, 0.2) * s, c + Vector2(-0.1, -0.5) * s]), ink, w * 1.6, true)
			ci.draw_circle(c + Vector2(0.35, 0.2) * s, s * 0.2, hot)
			ci.draw_circle(c + Vector2(-0.1, -0.5) * s, s * 0.16, ink)
		"laktisma":    # a kicking leg
			ci.draw_polyline(PackedVector2Array([c + Vector2(-0.5, -0.35) * s, c + Vector2(-0.05, 0.0) * s, c + Vector2(0.55, -0.2) * s]), ink, w * 1.6, true)
			ci.draw_line(c + Vector2(0.55, -0.2) * s, c + Vector2(0.62, -0.5) * s, hot, w * 1.5, true)
			ci.draw_arc(c + Vector2(-0.1, 0.1) * s, s * 0.62, -0.5, 0.9, 10, Color(hot, 0.6 * a), maxf(1.0, w * 0.5), true)
		"sweep":       # a low arc
			ci.draw_arc(c + Vector2(0, -0.1) * s, s * 0.6, 0.15, PI - 0.15, 14, hot, w * 1.3, true)
			ci.draw_line(c + Vector2(-0.6, 0.35) * s, c + Vector2(0.6, 0.35) * s, ink, w, true)
			ci.draw_circle(c + Vector2(0, -0.3) * s, s * 0.14, ink)
		"comet":       # a foot with a tail
			for k in 3:
				ci.draw_line(c + Vector2(-0.65, -0.5 + k * 0.22) * s, c + Vector2(-0.05, -0.1 + k * 0.12) * s, Color(hot, (0.4 + k * 0.2) * a), maxf(1.0, w * 0.6), true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.05, -0.2) * s, c + Vector2(0.6, 0.1) * s, c + Vector2(0.5, 0.4) * s,
				c + Vector2(-0.1, 0.25) * s]), ink)
		"guard":       # a round shield
			ci.draw_circle(c, s * 0.58, ink)
			ci.draw_circle(c, s * 0.4, Color(col.darkened(0.6), a))
			ci.draw_circle(c, s * 0.16, hot)
		"leap":        # a winged heel: an arc and a wing
			ci.draw_arc(c + Vector2(0, 0.55) * s, s * 0.75, PI + 0.5, TAU - 0.5, 14, hot, w, true)
			for k in 3:
				ci.draw_line(c + Vector2(-0.05, 0.25 - k * 0.04) * s, c + Vector2(0.55 - k * 0.12, -0.05 - k * 0.16) * s, ink, w, true)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.52, -0.6) * s, c + Vector2(0.7, -0.22) * s, c + Vector2(0.34, -0.3) * s]), hot)
		"lance":       # a beam
			ci.draw_line(c + Vector2(-0.6, 0.4) * s, c + Vector2(0.6, -0.4) * s, Color(col, 0.5 * a), w * 2.6, true)
			ci.draw_line(c + Vector2(-0.6, 0.4) * s, c + Vector2(0.6, -0.4) * s, hot, w, true)
			ci.draw_circle(c + Vector2(-0.55, 0.37) * s, s * 0.17, hot)
		"phlox":       # a fireball
			ci.draw_circle(c + Vector2(0.12, 0.08) * s, s * 0.42, Color(1.0, 0.45, 0.12, a))
			ci.draw_circle(c + Vector2(0.16, 0.1) * s, s * 0.24, Color(1.0, 0.9, 0.4, a))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-0.7, -0.55) * s, c + Vector2(0.05, -0.32) * s, c + Vector2(-0.28, 0.1) * s]),
				Color(1.0, 0.45, 0.12, a))
		"keraunos":    # a thunderbolt
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0.15, -0.7) * s, c + Vector2(-0.35, 0.05) * s, c + Vector2(-0.02, 0.05) * s,
				c + Vector2(-0.2, 0.7) * s, c + Vector2(0.4, -0.12) * s, c + Vector2(0.06, -0.12) * s]), hot)
		"aegis":       # a dome
			ci.draw_arc(c + Vector2(0, 0.35) * s, s * 0.62, PI, TAU, 16, hot, w, true)
			ci.draw_line(c + Vector2(-0.62, 0.35) * s, c + Vector2(0.62, 0.35) * s, ink, w, true)
			ci.draw_circle(c + Vector2(0, 0.2) * s, s * 0.13, ink)
		"eidola":      # three figures
			for k in 3:
				var o := c + Vector2(-0.4 + k * 0.4, 0.05 if k != 1 else -0.08) * s
				ci.draw_circle(o + Vector2(0, -0.3) * s, s * 0.13, hot if k == 1 else ink)
				ci.draw_line(o + Vector2(0, -0.15) * s, o + Vector2(0, 0.4) * s, hot if k == 1 else ink, w * 1.2, true)
		_:
			ci.draw_circle(c, s * 0.3, ink)
