class_name CosmosHull
extends RefCounted
## The 3D game's other ships' hulls: each in its empire's own design
## (EmpireHulls - from the empires' reference sheets), sized by class; the
## Minoan traders fly your ship's kind (MinoanShip). Built into `root` (its
## forward is -z); returns the engine nozzles' positions (for their glows).
##   var nozzles := CosmosHull.build(node, rng, "trader", "athens")

const SIZE := {"fighter": 1.0, "pirate": 1.1, "patrol": 1.4, "trader": 2.6, "freighter": 4.0, "hauler": 9.0}


## `empire`: whose it is ("pirates": a raider's; unknown: the independents' plain hull).
static func build(root: Node3D, rng: RandomNumberGenerator, kind: String, empire: String) -> Array:
	var reach: float = SIZE.get(kind, 1.0) * 11.0
	if empire == Galaxy.HOME_EMPIRE and kind in ["trader", "freighter", "hauler"]:
		return MinoanShip.place(root, reach * 2.0 / MinoanShip.LENGTH)
	return EmpireHulls.place(root, empire, kind, reach, rng.randi())


## Is the hull such a ship would wear made? (Its build is started if not: launch it later.)
static func ready(kind: String, empire: String) -> bool:
	if empire == Galaxy.HOME_EMPIRE and kind in ["trader", "freighter", "hauler"]:
		return CosmosShip.hull_ready()
	return EmpireHulls.ready(empire, kind)
