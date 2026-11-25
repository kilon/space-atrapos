class_name Affliction
extends RefCounted
## What a ship's damaged parts do to how it flies and fights, beyond weaker
## numbers (Parts: each part's "effects", scaled by how much of the part is
## lost): the same for your ship (Ship) and any other (Enemy - its own
## condition, damaged by hull hits through Parts.hit like yours).
##   "jitter"  (Manoeuvring Thrusters) - the ship jerks off its course and
##             wobbles: a random push now and then.
##   "misfire" (Weapon Mounts' fire control) - now and then it loses the target
##             and the guns fire wild for a second or two.
##   "scatter" (Sensor Array) - shots spread off the aim.
## Each takes `k`: the effect's size, 0 (sound) .. 1 (the part gone) - felt
## as its square root (a part a third gone already shows: _felt).
## One state dictionary per ship (new_state()), paced by time, not frames.

## How hard the worst jitter pushes, as a share of the ship's top speed.
const JITTER_PUSH := 0.4
## How far the worst jitter turns the nose (radians).
const JITTER_TURN := 0.22
## The fire control losing the target: chances a second at k = 1, and for how long (s).
const MISFIRE_RATE := 0.3
const MISFIRE_TIME := Vector2(1.0, 2.2)
## How wide wild shots go off the nose (radians, either way).
const WILD_ARC := 1.1
## The worst sensor scatter (radians, either way).
const SCATTER := 0.38


static func _felt(k: float) -> float:
	return sqrt(clampf(k, 0.0, 1.0))


static func new_state() -> Dictionary:
	return {"jt": 0.0, "jv": Vector2.ZERO, "jr": 0.0, "wild": 0.0}


## The thrusters' misfiring: a push (px/s per second, `speed`: the ship's top
## speed) - a new random kick every quarter to two-thirds of a second.
static func jitter_push(st: Dictionary, k: float, delta: float, speed: float) -> Vector2:
	if k <= 0.01:
		return Vector2.ZERO
	st["jt"] = float(st["jt"]) - delta
	if float(st["jt"]) <= 0.0:
		st["jt"] = randf_range(0.25, 0.7)
		st["jv"] = Vector2.from_angle(randf() * TAU) * randf_range(0.5, 1.0)
		st["jr"] = randf_range(-1.0, 1.0)
	return st["jv"] * _felt(k) * speed * JITTER_PUSH


## The nose's wobble from the thrusters (radians a second to turn by).
static func jitter_turn(st: Dictionary, k: float) -> float:
	return float(st["jr"]) * _felt(k) * JITTER_TURN * 6.0 if k > 0.01 else 0.0


## Is the fire control off its target now? Starts a wild spell at random
## (more often the worse the mounts); returns 1 the frame one starts, 2 while
## it lasts, 0 when it's on target.
static func misfire(st: Dictionary, k: float, delta: float) -> int:
	if float(st["wild"]) > 0.0:
		st["wild"] = float(st["wild"]) - delta
		return 2
	if k > 0.01 and randf() < _felt(k) * MISFIRE_RATE * delta:
		st["wild"] = randf_range(MISFIRE_TIME.x, MISFIRE_TIME.y)
		return 1
	return 0


## A wild shot's direction: somewhere ahead of the nose, not at the target.
static func wild_dir(facing: Vector2) -> Vector2:
	return facing.normalized().rotated(randf_range(-WILD_ARC, WILD_ARC))


## A shot's aim knocked off by damaged sensors.
static func scattered(dir: Vector2, k: float) -> Vector2:
	return dir.rotated(randf_range(-1.0, 1.0) * SCATTER * _felt(k)) if k > 0.01 else dir
