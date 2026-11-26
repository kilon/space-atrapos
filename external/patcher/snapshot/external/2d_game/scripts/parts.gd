class_name Parts
extends RefCounted
## Damage to the parts of your ship and your automaton, and their repair.
##
## Each body ("ship", "automaton") is made of PARTS (engines, reactor, legs,
## optics...), each part of components (circuits, conduits, servos, plates,
## lenses, power cells). Hits that get through to the hull (or the
## automaton's frame) can leave FAULTS in a part - a crack, burnt wiring, a
## leak, a misalignment, or a component wrecked outright - and a part's faults
## weaken what it does (a cracked engine: less speed; burnt optics: less
## reach). Faults are hidden until a scanner sees them: each kind shows in one
## scan mode (SCANS); the built-in scanner has two modes, the Mk II all four,
## the Mk III reads through a closed casing. They're fixed by hand in the
## Repair Bay (RepairBay): open the casing, scan, then the tool each fault needs
## (welder, soldering iron, sealant, calibrator, or forceps and a spare part).
## The automaton's body is anatomy in four layers (LAYERS: muscles, veins,
## nerves, skeleton) - its components are structures of a layer, at a place on
## the body, operated on like surgery (Surgery: SURGERY's tools).
##
## The state is one Dictionary - the player's "condition" (PlayerData.condition
## in space, state["player"]["condition"] on a planet: the same dictionary
## saved with the game):
##   {"ship": {part_id: {"faults": [fault...], "off": bool}}, "automaton": {...}, "next": int}
##   fault: {"id", "kind", "comp" (component index), "sev" (0.2..1), "found", "seed", "prog"}

## Scan modes: what each one shows.
const SCANS := {
	"structure": {"name": "Structure", "color": Color(0.55, 0.82, 1.0),
		"desc": "X-rays the frame: cracks and wrecked components show bright."},
	"thermal": {"name": "Thermal", "color": Color(1.0, 0.5, 0.2),
		"desc": "Heat and cold: a leak shows as a cold plume."},
	"field": {"name": "Field", "color": Color(0.75, 0.5, 1.0),
		"desc": "The current in the wiring: burnt wiring shows dark and sparking."},
	"resonance": {"name": "Resonance", "color": Color(0.45, 1.0, 0.6),
		"desc": "Vibration: a misaligned part hums off-key, in rings."},
}
const SCAN_ORDER := ["structure", "thermal", "field", "resonance"]

## Fault kinds. weight: how much of the part's work one (at full severity) takes away.
const FAULTS := {
	"crack": {"name": "Crack", "scan": "structure", "tool": "welder", "weight": 0.24,
		"desc": "A crack through the component: weld along it, slowly - too fast leaves it open, too long in one spot burns."},
	"burn": {"name": "Burnt wiring", "scan": "field", "tool": "solder", "weight": 0.26,
		"desc": "A burnt-through cable: join each strand to its own colour. Cut the part's power first, or it shocks."},
	"leak": {"name": "Leak", "scan": "thermal", "tool": "sealant", "weight": 0.22,
		"desc": "A leaking line: seal it while the pressure is low - sealant put on at high pressure is blown away."},
	"drift": {"name": "Misalignment", "scan": "resonance", "tool": "calibrator", "weight": 0.2,
		"desc": "A component knocked out of true: tune its frequency and phase to the reference until they agree."},
	"wreck": {"name": "Wrecked component", "scan": "structure", "tool": "forceps", "weight": 0.5,
		"desc": "Beyond repair: release its clamps, lift it out and fit a spare - turned the right way into its socket."},
}

## Which faults a component kind can have.
const COMP_FAULTS := {
	"circuit": ["burn", "crack", "wreck"],
	"conduit": ["leak", "crack", "wreck"],
	"servo": ["drift", "crack", "wreck"],
	"plate": ["crack", "wreck"],
	"lens": ["drift", "burn", "wreck"],
	"cell": ["leak", "burn", "wreck"],
}
## The spare part item each component kind takes.
const SPARE_OF := {"circuit": "spare_circuit", "conduit": "spare_conduit", "servo": "spare_servo",
	"plate": "spare_plate", "lens": "spare_lens", "cell": "spare_cell"}

## Damage type -> the fault kinds it tends to leave (in order of likelihood).
const DTYPE_FAULTS := {
	"kinetic": ["crack", "drift", "wreck"],
	"explosive": ["crack", "wreck", "drift", "leak"],
	"energy": ["burn", "crack", "drift"],
	"heat": ["leak", "burn", "crack"],
	"cold": ["crack", "leak"],
	"bio": ["leak", "burn"],
}

## The bodies. Each part: name, where it sits (the schematic: a polygon in a
## -1..1 box, the nose / the head up), which way hits reach it ("front", "rear",
## "side", "any"), what it does (effects at total loss: PlayerData.mod keys -
## the ship - or Gear effect keys - the automaton), and its components.
const BODIES := {
	"ship": {
		"name": "Ship",
		"parts": {
			"sensors": {"name": "Sensor Array", "faces": ["front"], "shape": [[0, -0.98], [0.16, -0.62], [-0.16, -0.62]],
				"effects": {"range_mult": -0.35, "scatter": 1.0, "accuracy": -0.25}, "what": "weapon range and aim (shots scatter)",
				"comps": [["lens", "Primary lens"], ["circuit", "Signal processor"], ["lens", "Rangefinder"], ["cell", "Sensor capacitor"]]},
			"weapons": {"name": "Weapon Mounts", "faces": ["front", "side"], "shape": [[-0.62, -0.18], [-0.3, -0.42], [0.3, -0.42], [0.62, -0.18], [0.5, -0.08], [-0.5, -0.08]],
				"effects": {"fire_rate_mult": 0.7, "damage_mult": -0.25, "misfire": 1.0}, "what": "rate of fire, damage and fire control (shots go wild)",
				"comps": [["servo", "Turret traverse"], ["circuit", "Fire control"], ["conduit", "Feed line"], ["plate", "Mount bracket"], ["cell", "Charge cell"]]},
			"reactor": {"name": "Reactor Core", "faces": ["any"], "shape": [[-0.18, -0.08], [0.18, -0.08], [0.22, 0.2], [0, 0.32], [-0.22, 0.2]],
				"effects": {"shield_regen_mult": -0.8}, "what": "shield recharge",
				"comps": [["cell", "Fusion cell"], ["conduit", "Coolant loop"], ["circuit", "Containment board"], ["plate", "Shielding"], ["conduit", "Plasma feed"]]},
			"shields": {"name": "Shield Emitter", "faces": ["any"], "shape": [[-0.3, -0.62], [0.3, -0.62], [0.3, -0.44], [-0.3, -0.44]],
				"effects": {"max_shields_mult": -0.55, "regen_delay": 3.0}, "what": "shield strength",
				"comps": [["lens", "Field projector"], ["circuit", "Emitter driver"], ["cell", "Buffer cell"], ["servo", "Phase rotor"]]},
			"thrusters": {"name": "Manoeuvring Thrusters", "faces": ["side"], "shape": [[-0.95, 0.12], [-0.62, -0.06], [-0.55, 0.36], [0.55, 0.36], [0.62, -0.06], [0.95, 0.12], [0.85, 0.42], [-0.85, 0.42]],
				"effects": {"handling_mult": -0.55, "jitter": 1.0}, "what": "turning, acceleration and steadiness (it jerks off course)",
				"comps": [["servo", "Port gimbal"], ["conduit", "RCS line"], ["servo", "Starboard gimbal"], ["circuit", "Attitude board"]]},
			"engines": {"name": "Main Engines", "faces": ["rear"], "shape": [[-0.4, 0.5], [0.4, 0.5], [0.46, 0.98], [-0.46, 0.98]],
				"effects": {"speed_mult": -0.45}, "what": "top speed",
				"comps": [["conduit", "Injector"], ["plate", "Nozzle liner"], ["servo", "Thrust vector"], ["circuit", "Ignition board"], ["cell", "Plasma chamber"]]},
			"fuel": {"name": "Fuel Lines", "faces": ["rear", "side"], "shape": [[-0.3, 0.32], [0.3, 0.32], [0.3, 0.48], [-0.3, 0.48]],
				"effects": {"fuel_leak": 1.2}, "what": "fuel (a leak drains the tank)",
				"comps": [["conduit", "Main line"], ["conduit", "Cross-feed"], ["servo", "Pump"], ["circuit", "Flow gauge"]]},
			"plating": {"name": "Hull Plating", "faces": ["any", "front", "side", "rear"], "shape": [[0, -0.6], [0.55, 0.0], [0.55, 0.5], [-0.55, 0.5], [-0.55, 0.0]],
				"effects": {"hull_taken_mult": 0.6}, "what": "armour (more hull damage taken)",
				"comps": [["plate", "Bow plate"], ["plate", "Keel plate"], ["plate", "Flank plate"], ["servo", "Frame strut"]]},
		},
	},
	# The automaton: a body, laid out as anatomy in four layers (LAYERS) -
	# each component a structure of one layer at a place on the body:
	# [kind, name, layer, x, z (metres: x across, + its left; z up from the
	# soles - AnatomyArt), the way it runs (degrees: 0 along the body, 90
	# across it), its half width (metres)]. Its muscles are its servos, its
	# vessels its conduits, its nerves its circuits, its bones its plates.
	"automaton": {
		"name": "Automaton",
		"parts": {
			"optics": {"name": "Optic Head", "faces": ["any"], "shape": [[-0.2, -0.98], [0.2, -0.98], [0.24, -0.66], [-0.24, -0.66]],
				"effects": {"range_mult": -0.4, "accuracy": -0.3}, "what": "weapon reach and aim",
				"comps": [["circuit", "Left optic nerve", "nerves", 0.018, 1.702, 90.0, 0.004], ["circuit", "Right facial nerve", "nerves", -0.062, 1.662, 80.0, 0.003],
					["servo", "Left neck muscle", "muscles", 0.045, 1.542, -18.0, 0.012], ["conduit", "Right carotid artery", "veins", -0.031, 1.545, 0.0, 0.006],
					["plate", "Jaw", "skeleton", 0.045, 1.592, 45.0, 0.012]]},
			"core": {"name": "Power Core", "faces": ["any"], "shape": [[-0.3, -0.58], [0.3, -0.58], [0.26, -0.12], [-0.26, -0.12]],
				"effects": {"regen_mult": -0.9, "max_hp": -40.0}, "what": "healing and health",
				"comps": [["servo", "Heart", "veins", 0.018, 1.335, 30.0, 0.036], ["conduit", "Aorta", "veins", -0.009, 1.420, 0.0, 0.014],
					["conduit", "Vena cava", "veins", -0.032, 1.416, 0.0, 0.011], ["plate", "Breastbone", "skeleton", 0.0, 1.360, 0.0, 0.019],
					["servo", "Left chest muscle", "muscles", 0.095, 1.395, -80.0, 0.040]], "vital": true},
			"arms": {"name": "Arm Actuators", "faces": ["any"], "shape": [[-0.62, -0.56], [-0.36, -0.56], [-0.32, 0.08], [-0.52, 0.12], [0.52, 0.12], [0.32, 0.08], [0.36, -0.56], [0.62, -0.56]],
				"effects": {"fire_rate_mult": 0.6, "damage_mult": -0.2}, "what": "rate of fire and damage",
				"comps": [["servo", "Right biceps", "muscles", -0.218, 1.300, 10.0, 0.019], ["servo", "Left forearm flexors", "muscles", 0.250, 1.060, -16.0, 0.012],
					["circuit", "Right median nerve", "nerves", -0.256, 1.040, 10.0, 0.003], ["conduit", "Right brachial artery", "veins", -0.229, 1.180, 11.0, 0.005],
					["plate", "Left upper arm bone", "skeleton", 0.213, 1.310, -7.0, 0.012]]},
			"cooling": {"name": "Heat Sinks", "faces": ["any"], "shape": [[-0.24, -0.1], [0.24, -0.1], [0.24, 0.1], [-0.24, 0.1]],
				"effects": {"fire_rate_mult": 0.3, "regen_mult": -0.3}, "what": "cooling (slower fire, slower healing)",
				"comps": [["conduit", "Left lung vessels", "veins", 0.110, 1.360, 60.0, 0.022], ["conduit", "Right lung vessels", "veins", -0.100, 1.310, 60.0, 0.022],
					["plate", "Left lower ribs", "skeleton", 0.150, 1.262, 8.0, 0.008], ["circuit", "Left phrenic nerve", "nerves", 0.059, 1.295, 0.0, 0.003],
					["servo", "Right chest muscle", "muscles", -0.100, 1.400, 80.0, 0.040]]},
			"legs": {"name": "Leg Servos", "faces": ["any"], "shape": [[-0.3, 0.14], [0.3, 0.14], [0.34, 0.98], [0.1, 0.98], [0, 0.4], [-0.1, 0.98], [-0.34, 0.98]],
				"effects": {"speed_mult": -0.45}, "what": "walking speed",
				"comps": [["servo", "Right thigh muscle", "muscles", -0.112, 0.760, 5.0, 0.023], ["servo", "Left shin muscle", "muscles", 0.105, 0.320, 0.0, 0.015],
					["conduit", "Left femoral artery", "veins", 0.078, 0.750, -3.0, 0.007], ["plate", "Left thigh bone", "skeleton", 0.1235, 0.675, -8.0, 0.015],
					["circuit", "Right sciatic nerve", "nerves", -0.096, 0.680, 2.0, 0.005]]},
			"frame": {"name": "Chassis Frame", "faces": ["any"], "shape": [[-0.34, -0.6], [0.34, -0.6], [0.34, 0.16], [-0.34, 0.16]],
				"effects": {"hurt_taken_mult": 0.5}, "what": "armour (more damage taken)",
				"comps": [["plate", "Lumbar spine", "skeleton", 0.0, 1.111, 0.0, 0.024], ["plate", "Right hip bone", "skeleton", -0.105, 1.030, 60.0, 0.030],
					["servo", "Abdominal wall", "muscles", 0.0385, 1.184, 0.0, 0.030], ["circuit", "Spinal cord", "nerves", 0.0, 1.330, 0.0, 0.008]]},
		},
	},
}

## The automaton's anatomy, outermost first (the operating table's layers: Surgery).
const LAYERS := ["muscles", "veins", "nerves", "skeleton"]
const LAYER_INFO := {
	"muscles": {"name": "Muscles", "color": Color(1.0, 0.45, 0.4), "desc": "The muscle bundles and their tendons - the surface: worked on directly."},
	"veins": {"name": "Veins", "color": Color(0.5, 0.7, 1.0), "desc": "The heart, the arteries and the veins - under the muscle: cut down to them."},
	"nerves": {"name": "Nerves", "color": Color(1.0, 0.85, 0.35), "desc": "The brain, the spinal cord and the nerves - under the muscle: cut down to them."},
	"skeleton": {"name": "Skeleton", "color": Color(0.92, 0.88, 0.76), "desc": "The bones - deepest: cut down to them."},
}
## The layers the built-in scanner shows faults in; a Mk II (or III) shows them all.
const BUILT_IN_LAYERS := ["muscles", "veins"]

## A fault in the automaton's body, by its kind and its layer ("" any): [name, tool, what to do].
const SURGERY := {
	"crack": {
		"skeleton": ["Fracture", "fuser", "A broken bone: trace the break with the bone fuser, slowly - too fast and it doesn't knit, too long in one spot overheats."],
		"": ["Tear", "suture", "Torn tissue: close it with sutures - a stitch at each mark along the tear."]},
	"burn": {"": ["Burnt nerve", "splicer", "A nerve burnt through: splice each fibre to its own colour. Numb the region first (the nerve block), or it shocks."]},
	"leak": {"": ["Bleeding vessel", "sealant", "A vessel leaking: clamp it upstream, then seal the hole while the pressure is down - sealant put on at high pressure is washed away."]},
	"drift": {"": ["Spasm", "tuner", "Firing out of rhythm: with the tuner, bring its rate and phase onto the reference wave and hold them there."]},
	"wreck": {"": ["Destroyed", "forceps", "Beyond repair: undo its two ties, lift it out and graft a spare - turned the way the tissue runs - then tie it in."]},
}

## Scanners: the modes they have (the built-in one always: structure and thermal).
const BUILT_IN_SCANS := ["structure", "thermal"]
const SCANNERS := {"scanner_mk2": ["structure", "thermal", "field", "resonance"],
	"scanner_mk3": ["structure", "thermal", "field", "resonance"]}
const MAX_FAULTS := 5     # per part
const HIT_CHANCE := 4.0   # a hit's chance to leave a fault: this x its share of the body's health


# --- The state -------------------------------------------------------------------

## The body's state in `cond` (made if missing): {part_id: {"faults": [], "off": false}}.
static func body(cond: Dictionary, which: String) -> Dictionary:
	if not cond.has(which) or not cond[which] is Dictionary:
		cond[which] = {}
	var b: Dictionary = cond[which]
	for pid in BODIES[which]["parts"]:
		if not b.has(pid) or not b[pid] is Dictionary:
			b[pid] = {"faults": [], "off": false}
		var p: Dictionary = b[pid]
		if not p.get("faults") is Array:
			p["faults"] = []
	return b


## A saved condition, cleaned up (JSON gives floats for ints; unknown parts and
## kinds dropped).
static func load_condition(saved: Variant) -> Dictionary:
	var out := {}
	if not saved is Dictionary:
		return out
	out["next"] = int(saved.get("next", 1))
	for which in BODIES:
		var b: Variant = saved.get(which)
		if not b is Dictionary:
			continue
		var nb := {}
		for pid in BODIES[which]["parts"]:
			var p: Variant = b.get(pid)
			if not p is Dictionary:
				continue
			var fs := []
			var n_comps: int = BODIES[which]["parts"][pid]["comps"].size()
			var cs: Array = BODIES[which]["parts"][pid]["comps"]
			for f in p.get("faults", []):
				if f is Dictionary and FAULTS.has(str(f.get("kind", ""))) and int(f.get("comp", -1)) in range(n_comps):
					# (An older save: the part's components were others then. A
					# fault its component can't have moves to one that can.)
					if not str(f["kind"]) in COMP_FAULTS[cs[int(f["comp"])][0]]:
						var to := -1
						for i in n_comps:
							if str(f["kind"]) in COMP_FAULTS[cs[i][0]] and not fs.any(func(x): return int(x["comp"]) == i):
								to = i
								break
						if to < 0:
							continue
						f["comp"] = to
					fs.append({"id": int(f.get("id", 0)), "kind": str(f["kind"]), "comp": int(f["comp"]),
						"sev": clampf(float(f.get("sev", 0.5)), 0.05, 1.0), "found": bool(f.get("found", false)),
						"seed": int(f.get("seed", 0)), "prog": float(f.get("prog", 0.0))})
			nb[pid] = {"faults": fs, "off": bool(p.get("off", false))}
		out[which] = nb
	return out


## The layer component `i` of a part belongs to ("" for the ship's).
static func comp_layer(which: String, pid: String, i: int) -> String:
	var c: Array = comps(which, pid)[i]
	return str(c[2]) if c.size() > 2 else ""


## A fault's name, the tool that mends it and what to do - the ship's by its
## kind (FAULTS), the automaton's by its kind and its layer (SURGERY).
static func fault_info(which: String, pid: String, f: Dictionary) -> Dictionary:
	var kind := str(f["kind"])
	var base: Dictionary = FAULTS[kind]
	if which != "automaton":
		return {"name": base["name"], "tool": base["tool"], "desc": base["desc"]}
	var layer := comp_layer(which, pid, int(f["comp"]))
	var e: Array = SURGERY[kind].get(layer, SURGERY[kind][""])
	var name: String = e[0]
	if kind == "drift" and str(comps(which, pid)[int(f["comp"])][1]) == "Heart":
		name = "Arrhythmia"
	return {"name": name, "tool": e[1], "desc": e[2]}


## The layers your scanner shows faults in.
static func scan_layers(items: Dictionary) -> Array:
	for id in SCANNERS:
		if int(items.get(id, 0)) > 0:
			return LAYERS
	return BUILT_IN_LAYERS


static func part(cond: Dictionary, which: String, pid: String) -> Dictionary:
	return body(cond, which)[pid]


static func info(which: String, pid: String) -> Dictionary:
	return BODIES[which]["parts"][pid]


static func comps(which: String, pid: String) -> Array:
	return BODIES[which]["parts"][pid]["comps"]


## How well a part works, 0..1 (its faults' weight off 1; switched off: 0).
static func health(cond: Dictionary, which: String, pid: String) -> float:
	var p := _peek(cond, which, pid)
	var loss := 0.0
	for f in p["faults"]:
		loss += float(f.get("sev", 0.5)) * float(FAULTS.get(str(f.get("kind", "crack")), FAULTS["crack"])["weight"])
	return clampf(1.0 - loss, 0.0, 1.0)


## The part's working share counting its power (off: none of it).
static func working(cond: Dictionary, which: String, pid: String) -> float:
	return 0.0 if _peek(cond, which, pid).get("off", false) else health(cond, which, pid)


const _NONE := {"faults": [], "off": false}

## A part's state without making it (none yet: no faults).
static func _peek(cond: Dictionary, which: String, pid: String) -> Dictionary:
	var b: Variant = cond.get(which)
	if b is Dictionary:
		var p: Variant = b.get(pid)
		if p is Dictionary and p.get("faults") is Array:
			return p
	return _NONE


static func fault_count(cond: Dictionary, which: String, found_only := false) -> int:
	var n := 0
	if not cond.has(which):
		return 0
	for pid in body(cond, which):
		for f in cond[which][pid]["faults"]:
			if not found_only or f.get("found", false):
				n += 1
	return n


## The sum of effect `key` over a body's parts: each part's effect times how
## much of it is lost (a ship's: added to PlayerData.mod; an automaton's: to
## its Gear effects).
static func mod(cond: Dictionary, which: String, key: String) -> float:
	if cond.is_empty() or not cond.has(which):
		return 0.0
	var total := 0.0
	for pid in BODIES[which]["parts"]:
		var e: Dictionary = BODIES[which]["parts"][pid]["effects"]
		if e.has(key):
			total += float(e[key]) * (1.0 - working(cond, which, pid))
	return total


## Every effect of a body's damage: {key: value} (only those not 0).
static func effects(cond: Dictionary, which: String) -> Dictionary:
	var out := {}
	if cond.is_empty() or not cond.has(which):
		return out
	for pid in BODIES[which]["parts"]:
		var loss := 1.0 - working(cond, which, pid)
		if loss <= 0.0:
			continue
		var e: Dictionary = BODIES[which]["parts"][pid]["effects"]
		for k in e:
			out[k] = float(out.get(k, 0.0)) + float(e[k]) * loss
	return out


## The scan modes you have (the built-in two, more with a scanner in your items).
static func scan_modes(items: Dictionary) -> Array:
	var out: Array = BUILT_IN_SCANS.duplicate()
	for s in SCANNERS:
		if int(items.get(s, 0)) > 0:
			for m in SCANNERS[s]:
				if not m in out:
					out.append(m)
	var sorted := []
	for m in SCAN_ORDER:
		if m in out:
			sorted.append(m)
	return sorted


## Reads through a closed casing (the Mk III)?
static func deep_scan(items: Dictionary) -> bool:
	return int(items.get("scanner_mk3", 0)) > 0


# --- Damage ------------------------------------------------------------------------

## A hit of `amount` (of the body's `max_health`) and type `dtype` from local
## direction `dir` (the ship: x right, -y ahead; ZERO: anywhere) - may leave a
## fault in one of the parts it reaches, or worsen one there. Returns the
## fault made or worsened ({} if none) with "part" added.
static func hit(cond: Dictionary, which: String, amount: float, max_health: float, dtype := "kinetic", dir := Vector2.ZERO, rng: RandomNumberGenerator = null) -> Dictionary:
	if amount <= 0.0 or max_health <= 0.0:
		return {}
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var chance := clampf(amount / max_health * HIT_CHANCE, 0.0, 0.85)
	if rng.randf() >= chance:
		return {}
	var pid := _pick_part(which, dir, rng)
	return add_fault(cond, which, pid, _pick_kind(dtype, rng), -1, rng)


## Puts a fault of `kind` in part `pid` (on component `comp`; -1: one that can
## have it) - or worsens the same fault already there. Returns it ({} if the
## part is full).
static func add_fault(cond: Dictionary, which: String, pid: String, kind: String, comp := -1, rng: RandomNumberGenerator = null) -> Dictionary:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	var p := part(cond, which, pid)
	var cs := comps(which, pid)
	if comp < 0:
		var fits := []
		for i in cs.size():
			if kind in COMP_FAULTS[cs[i][0]]:
				fits.append(i)
		if fits.is_empty():
			kind = "crack"
			fits = range(cs.size())
		comp = fits[rng.randi() % fits.size()]
	for f in p["faults"]:
		if int(f["comp"]) == comp and (f["kind"] == kind or f["kind"] == "wreck"):
			if f["kind"] != "wreck":
				f["sev"] = minf(1.0, float(f["sev"]) + 0.3)
				if float(f["sev"]) >= 1.0 and rng.randf() < 0.5:
					f["kind"] = "wreck"   # (beaten past repair: it needs a spare now)
					f["prog"] = 0.0
			var r: Dictionary = f.duplicate()
			r["part"] = pid
			return r
	if p["faults"].size() >= MAX_FAULTS:
		return {}
	var nid := int(cond.get("next", 1))
	cond["next"] = nid + 1
	var f := {"id": nid, "kind": kind, "comp": comp, "sev": snappedf(rng.randf_range(0.35, 0.75) if kind != "wreck" else 1.0, 0.01),
		"found": false, "seed": rng.randi() % 100000, "prog": 0.0}
	p["faults"].append(f)
	var r2 := f.duplicate()
	r2["part"] = pid
	return r2


## Takes fault `id` out of part `pid` (fixed). True if it was there.
static func clear_fault(cond: Dictionary, which: String, pid: String, id: int) -> bool:
	var fs: Array = part(cond, which, pid)["faults"]
	for i in fs.size():
		if int(fs[i]["id"]) == id:
			fs.remove_at(i)
			return true
	return false


## Repairs everything (a station's technicians).
static func clear_all(cond: Dictionary, which: String) -> int:
	var n := 0
	for pid in body(cond, which):
		n += cond[which][pid]["faults"].size()
		cond[which][pid]["faults"] = []
		cond[which][pid]["off"] = false
	return n


## What a station's technicians charge for fixing every fault of a body.
static func service_cost(cond: Dictionary, which: String) -> int:
	var c := 0.0
	if not cond.has(which):
		return 0
	for pid in body(cond, which):
		for f in cond[which][pid]["faults"]:
			c += 60.0 + 140.0 * float(f.get("sev", 0.5)) + (220.0 if f["kind"] == "wreck" else 0.0)
	return int(c)


static func _pick_part(which: String, dir: Vector2, rng: RandomNumberGenerator) -> String:
	var face := "any"
	if dir.length_squared() > 0.0001:
		var d := dir.normalized()
		face = "front" if d.y < -0.6 else ("rear" if d.y > 0.6 else "side")
	var pool := []
	for pid in BODIES[which]["parts"]:
		var faces: Array = BODIES[which]["parts"][pid]["faces"]
		var w := 1.0 if "any" in faces else 0.0
		if face != "any" and face in faces:
			w += 2.0
		elif face == "any":
			w = 1.0
		for i in int(w * 2.0):
			pool.append(pid)
	return pool[rng.randi() % pool.size()] if not pool.is_empty() else BODIES[which]["parts"].keys()[0]


static func _pick_kind(dtype: String, rng: RandomNumberGenerator) -> String:
	var kinds: Array = DTYPE_FAULTS.get(dtype, DTYPE_FAULTS["kinetic"])
	# The first is likeliest: weights 4, 2, 1, 1...
	var pool := []
	for i in kinds.size():
		for k in [4, 2, 1, 1, 1][mini(i, 4)]:
			pool.append(kinds[i])
	return pool[rng.randi() % pool.size()]


# --- Afflictions: what the damage does, shown under the health bar --------------------------
# Each damaged part is an affliction (its effects at its loss: weaker, slower,
# jerking about...), and the first of them is always the same: while anything
# is damaged the body's self-repair stops (the ship's hull, the automaton's
# health) - REGEN. They go when the part is mended (the Repair Bay, a station).
# The worse the body is hurt the more there are: a hit that leaves it below a
# share of its health brings faults up to that share's count (by_health).

const REGEN_NAME := "Self-repair frozen"
## Faults a body has at least, by how much of its health is gone: at 100% - 0, below 80% - 1 ... below 15% - 5.
const HEALTH_STEPS := [0.8, 0.6, 0.4, 0.25, 0.15]


## Is the body's self-repair stopped (anything in it damaged)?
static func regen_frozen(cond: Dictionary, which: String) -> bool:
	return fault_count(cond, which) > 0


## The afflictions now: [{id, name, desc, part, loss}] - the frozen self-repair
## first, then a damaged part each, the worst first.
static func afflictions(cond: Dictionary, which: String) -> Array:
	var out := []
	if cond.is_empty() or not cond.has(which) or fault_count(cond, which) == 0:
		return out
	var body_name: String = "hull" if which == "ship" else "health"
	out.append({"id": "regen", "name": REGEN_NAME, "part": "", "loss": 1.0,
		"desc": "Something is damaged: the %s stops mending itself until every damaged part is repaired." % body_name})
	var parts := []
	for pid in BODIES[which]["parts"]:
		var loss := 1.0 - working(cond, which, pid)
		var fs: Array = _peek(cond, which, pid)["faults"]
		if fs.is_empty() and loss <= 0.0:
			continue
		parts.append([loss, pid])
	parts.sort_custom(func(a, b): return a[0] > b[0])
	for e in parts:
		var pid: String = e[1]
		var p: Dictionary = info(which, pid)
		var fx := []
		for k in p["effects"]:
			fx.append(effect_words(k, float(p["effects"][k]) * float(e[0])))
		var faults := []
		for f in _peek(cond, which, pid)["faults"]:
			var fi := fault_info(which, pid, f)
			faults.append("%s - %s%s" % [fi["name"], str(comps(which, pid)[int(f["comp"])][1]).to_lower(), "" if f.get("found", false) else " (not yet traced)"])
		var off: bool = _peek(cond, which, pid).get("off", false)
		out.append({"id": pid, "part": pid, "loss": float(e[0]),
			"name": "%s %s" % [p["name"], "switched off" if off else "damaged"],
			"desc": "Working at %d%%: %s.\n%s" % [roundi((1.0 - float(e[0])) * 100.0), ", ".join(fx.filter(func(x): return x != "")),
				"\n".join(faults.map(func(x): return "  · " + x))]})
	return out


## An effect at its size, in words ("top speed -22%").
static func effect_words(key: String, v: float) -> String:
	if absf(v) < 0.005:
		return ""
	match key:
		"speed_mult": return "speed %d%%" % roundi(v * 100.0)
		"handling_mult": return "handling %d%%" % roundi(v * 100.0)
		"range_mult": return "weapon reach %d%%" % roundi(v * 100.0)
		"damage_mult": return "damage %d%%" % roundi(v * 100.0)
		"fire_rate_mult": return "rate of fire -%d%%" % roundi(v / (1.0 + v) * 100.0)
		"shield_regen_mult": return "shield recharge %d%%" % roundi(v * 100.0)
		"max_shields_mult": return "shields %d%%" % roundi(v * 100.0)
		"regen_delay": return "shields recharge %.1f s later" % v
		"hull_taken_mult", "hurt_taken_mult": return "damage taken +%d%%" % roundi(v * 100.0)
		"regen_mult": return "healing %d%%" % roundi(v * 100.0)
		"max_hp": return "health %d" % roundi(v)
		"fuel_leak": return "leaking fuel"
		"jitter": return "jerks off course"
		"misfire": return "fire control loses the target"
		"scatter": return "shots scatter"
		"accuracy": return "accuracy %d%%" % roundi(v * 100.0)
	return "%s %+.0f%%" % [key, v * 100.0]


## A hit left the body at `frac` of its health: it has at least as many faults
## as that's worth (HEALTH_STEPS) - new ones where they're missing. The faults made.
static func by_health(cond: Dictionary, which: String, frac: float, dtype := "kinetic", rng: RandomNumberGenerator = null) -> Array:
	var want := 0
	for st in HEALTH_STEPS:
		if frac < st:
			want += 1
	var made := []
	var tries := 0
	while fault_count(cond, which) < want and tries < 12:
		tries += 1
		if rng == null:
			rng = RandomNumberGenerator.new()
			rng.randomize()
		var pid := _pick_part(which, Vector2.ZERO, rng)
		var f := add_fault(cond, which, pid, _pick_kind(dtype, rng), -1, rng)
		if not f.is_empty():
			made.append(f)
	return made


## A line for the log when a hit leaves (or worsens) a fault.
static func hit_text(which: String, f: Dictionary) -> String:
	var p: Dictionary = info(which, str(f["part"]))
	return "%s damaged: %s down. Scan it in the Repair Bay." % [p["name"], p["what"].get_slice(" (", 0)]
