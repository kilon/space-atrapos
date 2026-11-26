class_name CosmosStationProxy
extends Node2D
## A 3D station as the game's Station Menu sees it (stage 5: the hangar's
## terminals open the real menu - market, outfitting, weapons, shipyard,
## missions, repairs): its id, name, empire and health, in map units.

var station_id := ""
var station_name := ""
var empire := ""
var accent := Color(0.3, 0.85, 1.0)
var _health := 100.0


func setup(st: CosmosStation) -> void:
	station_id = str(st.record.get("id", ""))
	station_name = str(st.record.get("name", "Station"))
	empire = str(st.record.get("empire", ""))
	accent = Galaxy.empire_color(empire)
	_health = float(Galaxy.station_health(station_id)) if Galaxy.stations.has(station_id) else 100.0


func health() -> float:
	return _health
