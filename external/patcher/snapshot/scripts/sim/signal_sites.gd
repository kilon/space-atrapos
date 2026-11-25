class_name SignalSites
## Signal sources: points of interest hidden in every star system, found by a
## system scan (ShipScanner, right-click in empty space). Each is a kind of
## encounter - a classic of space games - played out in a pocket
## of empty space you drop into from its beacon (SignalBeacon -> SignalSite):
##   stranded     a ship out of fuel calls for help (give it fuel: a reward -
##                sometimes it's bait and pirates jump you)
##   under_attack a freighter fighting off pirates (save it: its thanks)
##   wreck        a shipwreck with its cargo scattered round it (loot; maybe
##                scavengers)
##   monster      an alien creature; it drops rare loot when it dies
##   anomaly      a space anomaly: scan its four nodes for research data
##   deathtrap    a field of unstable anomalies that drain your shields and
##                burn your hull - cross it to its exit for what's there
## Each system gets a fresh set every EPOCH seconds of galaxy time (the ones
## you've found and not finished stay). Galaxy.signals_in() keeps them.
## Each has a level (LEVELS: easy, moderate, hard, insane - level()), shown
## wherever it is (its beacon, the scan, the site's panel): its hostile ships
## and creatures have their hull and shields x mult and deal damage x mult
## (SignalSite._spawn, Enemy.damage_mult), its hazards burn x mult - and its
## rewards are x mult too.

const EPOCH := 1200.0
const KINDS := {
	"stranded": {"name": "Distress call", "detail": "A ship is calling for help - out of fuel.", "color": Color(1.0, 0.75, 0.3)},
	"under_attack": {"name": "Combat signal", "detail": "Weapons fire - a freighter under attack.", "color": Color(1.0, 0.4, 0.3)},
	"wreck": {"name": "Debris field", "detail": "A wrecked ship, its cargo drifting round it.", "color": Color(0.7, 0.8, 0.9)},
	"monster": {"name": "Unknown bio-signature", "detail": "Something alive and very large.", "color": Color(0.45, 1.0, 0.55)},
	"anomaly": {"name": "Anomalous readings", "detail": "A space anomaly - scan it for research data.", "color": Color(0.5, 0.75, 1.0)},
	"deathtrap": {"name": "Hazard: anomaly field", "detail": "Unstable anomalies drain shields and burn hulls. Something waits at the far side.", "color": Color(0.85, 0.45, 1.0)},
	# Not a signal: a ringed planet's ring (main.gd puts its beacon on the ring).
	"ring": {"name": "Ring field", "detail": "The planet's ring: ice asteroids beyond counting, the miners who cut them, the pirates who prey on them.", "color": Color(0.7, 0.9, 1.0)},
}
## The kinds signal sources come as (the rings are not signals).
static func signal_kinds() -> Array:
	return KINDS.keys().filter(func(k): return k != "ring")


const COUNT := [12, 36]          # signals a system has, each epoch
const RING := [4000.0, 16000.0]  # their distance from the star
const APART := 1500.0            # at least this far from each other


## A system's signals for one epoch: COUNT[0]-COUNT[1] of them - every kind
## at least once (the first six, shuffled), then kinds at random - RING away
## from the star and APART from each other (the same every time for the
## same system and epoch).
static func generate(sys_id: String, epoch: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%d" % [sys_id, epoch])
	var kinds: Array = signal_kinds()
	for k in range(kinds.size() - 1, 0, -1):
		var m := rng.randi() % (k + 1)
		var t = kinds[k]
		kinds[k] = kinds[m]
		kinds[m] = t
	var n := rng.randi_range(COUNT[0], COUNT[1])
	var all: Array = signal_kinds()
	while kinds.size() < n:
		kinds.append(all[rng.randi() % all.size()])
	var out := []
	var spots: Array = []
	for i in n:
		var p := Vector2.ZERO
		for attempt in 40:   # (somewhere not on top of another signal)
			p = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(RING[0], RING[1])
			if spots.all(func(q): return q.distance_to(p) >= APART):
				break
		spots.append(p)
		var sg := {"id": "%s:%d:%d" % [sys_id, epoch, i], "kind": kinds[i], "pos": [p.x, p.y],
			"located": false, "done": false, "seed": rng.randi()}
		sg["level"] = level(sg)
		out.append(sg)
	return out


const LEVELS := {
	"easy": {"name": "Easy", "mult": 0.75, "color": Color(0.45, 1.0, 0.5)},
	"moderate": {"name": "Moderate", "mult": 1.0, "color": Color(1.0, 0.9, 0.35)},
	"hard": {"name": "Hard", "mult": 1.5, "color": Color(1.0, 0.55, 0.2)},
	"insane": {"name": "Insane", "mult": 2.25, "color": Color(1.0, 0.25, 0.3)},
}
const LEVEL_ODDS := [["easy", 30], ["moderate", 35], ["hard", 23], ["insane", 12]]   # (percent)


## A signal's level: drawn from its seed (the same every time; old saves'
## signals get theirs the same way).
static func level(sig: Dictionary) -> String:
	if LEVELS.has(sig.get("level", "")):
		return sig["level"]
	var roll := absi(hash("level:%s" % str(sig.get("seed", sig.get("id", ""))))) % 100
	for l in LEVEL_ODDS:
		roll -= int(l[1])
		if roll < 0:
			return l[0]
	return "moderate"


static func level_info(sig: Dictionary) -> Dictionary:
	return LEVELS[level(sig)]


## Hull, shields, damage and rewards are multiplied by this.
static func mult(sig: Dictionary) -> float:
	return float(level_info(sig)["mult"])


## "Unknown bio-signature (Hard)".
static func title(sig: Dictionary) -> String:
	return "%s (%s)" % [info(str(sig.get("kind", "wreck")))["name"], level_info(sig)["name"]]


static func info(kind: String) -> Dictionary:
	return KINDS.get(kind, KINDS["wreck"])


static func pos(sig: Dictionary) -> Vector2:
	return Vector2(float(sig["pos"][0]), float(sig["pos"][1]))
