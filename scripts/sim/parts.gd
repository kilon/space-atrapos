class_name Parts
extends RefCounted
## The parts of your ship and your automaton, by name - where their component
## upgrades live (Upgrades.STATS: a body's parts, each with its stats).
##   Parts.info("ship", "engines")["name"]   # "Main Engines"

const BODIES := {
	"ship": {
		"name": "Ship",
		"parts": {
			"sensors": {"name": "Sensor Array", "what": "weapon range and aim"},
			"weapons": {"name": "Weapon Mounts", "what": "rate of fire, damage and fire control"},
			"reactor": {"name": "Reactor Core", "what": "shield recharge"},
			"shields": {"name": "Shield Emitter", "what": "shield strength"},
			"thrusters": {"name": "Manoeuvring Thrusters", "what": "turning, acceleration and steadiness"},
			"engines": {"name": "Main Engines", "what": "top speed"},
			"fuel": {"name": "Fuel Lines", "what": "fuel"},
			"plating": {"name": "Hull Plating", "what": "armour"},
		},
	},
	"automaton": {
		"name": "Automaton",
		"parts": {
			"optics": {"name": "Optic Head", "what": "weapon reach and aim"},
			"core": {"name": "Power Core", "what": "healing and health"},
			"arms": {"name": "Arm Actuators", "what": "rate of fire and damage"},
			"cooling": {"name": "Heat Sinks", "what": "cooling"},
			"legs": {"name": "Leg Servos", "what": "walking speed"},
			"frame": {"name": "Chassis Frame", "what": "armour"},
		},
	},
}


static func info(which: String, pid: String) -> Dictionary:
	return BODIES[which]["parts"][pid]
