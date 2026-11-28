class_name CosmosHull
extends RefCounted
## The 3D game's other ships' hulls: each in its empire's own design
## (EmpireHulls - from the empires' reference sheets), sized by class; the
## Minoan traders fly your ship's kind (MinoanShip). Built into `root` (its
## forward is -z); returns the engine nozzles' positions (for their glows).
##   var nozzles := CosmosHull.build(node, rng, "trader", "athens")

const SIZE := {"fighter": 1.0, "pirate": 1.1, "patrol": 1.4, "shuttle": 1.6, "trader": 2.6, "freighter": 4.0, "hauler": 9.0}
## (a "shuttle" - a town's landing field's traffic, CosmosLandingField - wears its trader's design, smaller: room
## inside for a pilot and a passenger - a little bigger for the slimmer designs, so there's still room)
const DESIGN := {"shuttle": "trader"}
const SHUTTLE := {"athens": 1.8, "cyclades": 2.0}


## A ship's size (its half length / 11 m) of `kind` and `empire`.
static func size_of(kind: String, empire: String) -> float:
	if kind == "shuttle":
		return float(SHUTTLE.get(empire, SIZE["shuttle"]))
	return float(SIZE.get(kind, 1.0))


## `empire`: whose it is ("pirates": a raider's; unknown: the independents' plain hull).
static func build(root: Node3D, rng: RandomNumberGenerator, kind: String, empire: String) -> Array:
	var reach: float = size_of(kind, empire) * 11.0
	kind = DESIGN.get(kind, kind)
	if empire == Galaxy.HOME_EMPIRE and kind in ["trader", "freighter", "hauler"]:
		return MinoanShip.place(root, reach * 2.0 / MinoanShip.LENGTH)
	return EmpireHulls.place(root, empire, kind, reach, rng.randi())


## Is the hull such a ship would wear made? (Its build is started if not: launch it later.)
static func ready(kind: String, empire: String) -> bool:
	kind = DESIGN.get(kind, kind)
	if empire == Galaxy.HOME_EMPIRE and kind in ["trader", "freighter", "hauler"]:
		return CosmosShip.hull_ready()
	return EmpireHulls.ready(empire, kind)
