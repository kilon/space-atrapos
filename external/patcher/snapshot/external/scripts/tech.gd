class_name Tech
## Tech tree: 5 branches × 3 tiers. Each tech needs the previous tier of its
## branch, costs credits (top tier also Data Cores) and adds stat modifiers.
##
## Effect keys (summed over unlocked techs, read with PlayerData.mod()):
##   max_hull, max_shields, hull_regen (per second), regen_delay (seconds),
##   shield_regen_mult, damage_mult, fire_rate_mult (negative = faster),
##   range_mult, speed_mult, handling_mult, afterburner_cd_mult,
##   magnet_mult, loot_mult

const BRANCHES := [
	{"id": "hull", "name": "HULL", "color": Color(0.45, 0.95, 0.5)},
	{"id": "shields", "name": "SHIELDS", "color": Color(0.35, 0.8, 1.0)},
	{"id": "weapons", "name": "WEAPONS", "color": Color(1.0, 0.45, 0.35)},
	{"id": "engines", "name": "ENGINES", "color": Color(1.0, 0.7, 0.25)},
	{"id": "salvage", "name": "SALVAGE", "color": Color(0.8, 0.55, 1.0)},
]

const TECHS := {
	# Hull
	"hull_1": {"name": "Reinforced Hull", "branch": "hull", "tier": 0, "cost": 300, "cores": 0,
		"effects": {"max_hull": 25.0}, "short": "+25 max hull",
		"desc": "Extra armour plating welded over the frame."},
	"hull_2": {"name": "Composite Armour", "branch": "hull", "tier": 1, "cost": 700, "cores": 0,
		"effects": {"max_hull": 50.0}, "short": "+50 max hull",
		"desc": "Layered ceramic-alloy armour. Heavy, but worth it."},
	"hull_3": {"name": "Nanite Regeneration", "branch": "hull", "tier": 2, "cost": 1200, "cores": 2,
		"effects": {"hull_regen": 1.5}, "short": "Hull repairs 1.5/s",
		"desc": "Nanites slowly rebuild damaged plating, even in combat."},
	# Shields
	"shields_1": {"name": "Shield Capacitors", "branch": "shields", "tier": 0, "cost": 300, "cores": 0,
		"effects": {"max_shields": 25.0}, "short": "+25 max shields",
		"desc": "Bigger capacitor banks hold more shield energy."},
	"shields_2": {"name": "Rapid Recharge", "branch": "shields", "tier": 1, "cost": 650, "cores": 0,
		"effects": {"shield_regen_mult": 0.75, "regen_delay": -1.0}, "short": "+75% regen, starts 1 s sooner",
		"desc": "Improved field emitters recover from hits much faster."},
	"shields_3": {"name": "Hardened Shields", "branch": "shields", "tier": 2, "cost": 1100, "cores": 2,
		"effects": {"max_shields": 60.0}, "short": "+60 max shields",
		"desc": "Military-grade layered shield matrix."},
	# Weapons
	"weapons_1": {"name": "Focused Emitters", "branch": "weapons", "tier": 0, "cost": 350, "cores": 0,
		"effects": {"damage_mult": 0.2}, "short": "+20% weapon damage",
		"desc": "Tighter beam focus and hotter plasma for every weapon."},
	"weapons_2": {"name": "Rapid Cycling", "branch": "weapons", "tier": 1, "cost": 800, "cores": 0,
		"effects": {"fire_rate_mult": -0.2}, "short": "Weapons fire 20% faster",
		"desc": "Better cooling lets the guns cycle faster."},
	"weapons_3": {"name": "Long-Range Targeting", "branch": "weapons", "tier": 2, "cost": 1300, "cores": 2,
		"effects": {"range_mult": 0.25, "damage_mult": 0.15}, "short": "+25% range, +15% damage",
		"desc": "Advanced fire-control computer. Hit them before they hit you."},
	# Engines
	"engines_1": {"name": "Tuned Thrusters", "branch": "engines", "tier": 0, "cost": 250, "cores": 0,
		"effects": {"speed_mult": 0.15}, "short": "+15% top speed",
		"desc": "Recalibrated thrusters squeeze out more speed."},
	"engines_2": {"name": "Vector Control", "branch": "engines", "tier": 1, "cost": 600, "cores": 0,
		"effects": {"handling_mult": 0.4}, "short": "+40% turning & acceleration",
		"desc": "Manoeuvring jets make the ship far more agile."},
	"engines_3": {"name": "Afterburner Mk II", "branch": "engines", "tier": 2, "cost": 900, "cores": 1,
		"effects": {"afterburner_cd_mult": -0.5, "speed_mult": 0.1}, "short": "Afterburner cooldown -50%, +10% speed",
		"desc": "Reinforced combustion chamber. Needs an Afterburner to benefit fully."},
	# Salvage
	"salvage_1": {"name": "Tractor Beam", "branch": "salvage", "tier": 0, "cost": 200, "cores": 0,
		"effects": {"magnet_mult": 1.0}, "short": "Loot pulled in from 2x range",
		"desc": "Pulls floating loot toward the ship from much further away."},
	"salvage_2": {"name": "Salvage Expert", "branch": "salvage", "tier": 1, "cost": 500, "cores": 0,
		"effects": {"loot_mult": 0.3}, "short": "+30% drachmas from wrecks",
		"desc": "Know what to strip from a wreck and what to leave."},
	"salvage_3": {"name": "Deep Scanner", "branch": "salvage", "tier": 2, "cost": 900, "cores": 1,
		"effects": {"loot_mult": 0.4, "magnet_mult": 0.5}, "short": "+40% more drachmas, wider pull",
		"desc": "Finds hidden compartments full of valuables in every wreck."},
}


static func ids_in_branch(branch: String) -> Array:
	var out := []
	for id in TECHS:
		if TECHS[id]["branch"] == branch:
			out.append(id)
	out.sort_custom(func(a, b): return TECHS[a]["tier"] < TECHS[b]["tier"])
	return out


## The tech this one requires (previous tier in the branch), or "".
static func prerequisite(id: String) -> String:
	var t: Dictionary = TECHS[id]
	if t["tier"] == 0:
		return ""
	return ids_in_branch(t["branch"])[t["tier"] - 1]


static func branch_color(branch: String) -> Color:
	for b in BRANCHES:
		if b["id"] == branch:
			return b["color"]
	return Color.WHITE
