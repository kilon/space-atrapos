class_name CosmosLair
extends Node3D
## A monster signal in the 3D game (SignalSites "monster", Galaxy.signals_in):
## "Unknown bio-signature" on the HUD - target it (T), fly there; within
## Cosmos.LAIR_NEAR its creature (CosmosMonster) is out. Done when it dies.

var sig := {}
var monster: Node3D = null


func title() -> String:
	return "Unknown bio-signature (%s)" % str(SignalSites.level_info(sig).get("name", ""))


## Which creature lives here (by the signal's seed).
func kind() -> String:
	return CosmosMonster.KINDS[absi(int(sig.get("seed", 0))) % CosmosMonster.KINDS.size()]
