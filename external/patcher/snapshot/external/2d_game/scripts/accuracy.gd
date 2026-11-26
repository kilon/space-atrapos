class_name Accuracy
extends RefCounted
## Whether a shot lands. Every shooter has an accuracy - its chance to hit a
## still target at close range (your ship: BASE_SHIP and its upgrades; NPC
## ships by class; the automaton: BASE_FOOT and its gear; pirates, beasts) -
## less the target's evasion (its own stat, and how fast it moves across the
## line of fire) and a little more the further it is (beyond half the reach).
## A miss isn't a hit that does nothing: the shot is aimed past the target,
## beside it (miss_dir) and flies on by - it never touches it.

const BASE_SHIP := 0.86
const BASE_FOOT := 0.88
## NPC ships' accuracy by hull class.
const NPC := {"interceptor": 0.74, "fighter": 0.74, "courier": 0.68, "explorer": 0.68, "freighter": 0.62,
	"gunship": 0.72, "frigate": 0.70, "cruiser": 0.70, "battleship": 0.68, "dreadnought": 0.68}
const MIN_HIT := 0.05
const MAX_HIT := 0.98


## The chance a shot from `from` (accuracy `acc`, reach `reach`) lands on `target`.
static func chance(acc: float, from: Vector2, target: Node2D, reach := 800.0) -> float:
	if not is_instance_valid(target):
		return 0.0
	var tp: Vector2 = target.global_position
	var d := from.distance_to(tp)
	var ev := float(target.get("evasion")) if target.get("evasion") != null else 0.0
	# Moving across the line of fire is harder to hit than coming straight on.
	var v = target.get("velocity")
	if v is Vector2 and d > 1.0:
		var across := absf((v as Vector2).cross((tp - from) / d))
		ev += 0.12 * clampf(across / 450.0, 0.0, 1.0)
	var far := 0.15 * clampf(d / maxf(1.0, reach) - 0.5, 0.0, 1.0)
	return clampf(acc * (1.0 - ev) - far, MIN_HIT, MAX_HIT)


## Every shot lands (tests that measure something other than aim: a beam's drain, a fight's turn).
static var sure := false

static func roll(acc: float, from: Vector2, target: Node2D, reach := 800.0) -> bool:
	return sure or randf() < chance(acc, from, target, reach)


## A missed shot's direction: from `from` toward a point beside `aim`, clear
## of a target of radius `r` (by 1.3 to 2.2 of it, either side).
static func miss_dir(from: Vector2, aim: Vector2, r: float) -> Vector2:
	var to := aim - from
	var side := to.orthogonal().normalized() * (1.0 if randf() < 0.5 else -1.0)
	return from.direction_to(aim + side * r * randf_range(1.3, 2.2))
